package BalanceOfPower::Nation;

use strict;
use v5.10;

use Moo;

use BalanceOfPower::Utils qw( prev_turn );
use BalanceOfPower::Constants ':all';

with 'BalanceOfPower::Role::Reporter';
with 'BalanceOfPower::Nation::Role::IA';

has name => (
    is => 'ro',
    default => 'Dummyland'
);
has area => (
    is => 'ro',
    default => 'Neverwhere'
);


has export_quote => (
    is => 'ro',
    default => 50
);
has government => (
    is => 'ro',
    default => 'democracy'
);
has government_strength => (
    is => 'rw',
    default => 70
);
has size => (
    is => 'ro',
    default => 1
);

has internal_disorder => (
    is => 'rw',
    default => 0
);
has production_for_domestic => (
    is => 'rw',
    default => 0
);
has production_for_export => (
    is => 'rw',
    default => 0
);
has prestige => (
    is => 'rw',
    default => 0
);
has wealth => (
    is => 'rw',
    default => 0
);
has debt => (
    is => 'rw',
    default => 0
);
has rebel_provinces => (
    is => 'rw',
    default => 0
);
has current_year => (
    is => 'rw'
);

has army => (
    default => 0,
    is => 'rw'
);

sub production
{
    my $self = shift;
    my $prod = shift;
    if($prod)
    {
        if($prod <= DEBT_TO_RAISE_LIMIT && $self->debt < MAX_DEBT && DEBT_ALLOWED)
        {
            $prod += PRODUCTION_THROUGH_DEBT;
            $self->debt($self->debt + 1);
            $self->register_event("DEBT RISE");
        }
        if($self->government eq 'dictatorship')
        {
            $prod -= DICTATORSHIP_PRODUCTION_MALUS;
        }
        my $internal = $prod - (($self->export_quote * $prod) / 100);
        my $export = $prod - $internal;
        $self->production_for_domestic($internal);
        $self->production_for_export($export);
        $self->register_event("PRODUCTION INT: $internal EXP: $export");
    }
    return $self->production_for_domestic + $self->production_for_export;
}

sub calculate_internal_wealth
{
    my $self = shift;
    my $internal_production = $self->production_for_domestic();
    $self->add_wealth($internal_production * INTERNAL_PRODUCTION_GAIN);
    $self->production_for_domestic(0);
    $self->register_event("INTERNAL " . $internal_production);
}

sub calculate_trading
{
    my $self = shift;
    my $world = shift;
    my @routes = $world->routes_for_node($self->name);
    my %diplomacy = $world->diplomacy_for_node($self->name);
    @routes = sort { $b->factor_for_node($self->name) * 1000 + $diplomacy{$b->destination($self->name)}
                     <=>
                     $a->factor_for_node($self->name) * 1000 + $diplomacy{$a->destination($self->name)}
                   } @routes;
    if(@routes > 0)
    {
        foreach my $r (@routes)
        {
           if($self->production_for_export >= TRADING_QUOTE)
           {
                my $treaty_bonus = 0;
                if($world->exists_treaty_by_type($self->name, $r->destination($self->name), 'commercial'))
                {
                    $treaty_bonus = TREATY_TRADE_FACTOR;
                }
                $self->trade(TRADING_QUOTE, $r->factor_for_node($self->name) + $treaty_bonus);
                my $event = "TRADE OK " . $r->destination($self->name) . " [x" . $r->factor_for_node($self->name);
                if($treaty_bonus > 0)
                {
                    $event .= " +$treaty_bonus";
                }
                $event .= "]";
                $self->register_event($event);
           }
           else
           {
                $self->trade(0, $r->factor_for_node($self->name));
                $self->register_event("TRADE KO " . $r->destination($self->name));
           }     
        }
    }
}

sub convert_remains
{
    my $self = shift;
    $self->add_wealth($self->production);
    $self->register_event("REMAIN " . $self->production);
    $self->production_for_domestic(0);
    $self->production_for_export(0);
}

sub war_cost
{
    my $self = shift;
    $self->add_wealth(-1 * WAR_WEALTH_MALUS);
    $self->register_event("WAR COST PAYED: " . WAR_WEALTH_MALUS);
}

sub boost_production
{
    my $self = shift;
    my $boost = BOOST_PRODUCTION_QUOTE * PRODUCTION_UNITS->[$self->size];
    $self->subtract_production('export', -1 * $boost);
    $self->subtract_production('domestic', -1 * $boost);
    $self->register_event("BOOST OF PRODUCTION");
}
sub receive_aid
{
    my $self = shift;
    my $from = shift;
    my $boost = ECONOMIC_AID_QUOTE * PRODUCTION_UNITS->[$self->size];
    $self->subtract_production('export', -1 * $boost);
    $self->subtract_production('domestic', -1 * $boost);
}

sub trade
{
    my $self = shift;
    my $production = shift;
    my $gain = shift;
    $self->subtract_production('export', $production);
    $self->add_wealth($production * $gain);
    $self->add_wealth(-1 * TRADINGROUTE_COST);
}

sub calculate_disorder
{
    my $self = shift;
    my $world = shift;
    return if($self->internal_disorder_status eq 'Civil war');

    #Variables
    my $wd = $self->wealth / PRODUCTION_UNITS->[$self->size];
    my $d = $self->internal_disorder;
    my $g = $self->government_strength;

    #Constants
    my $wd_middle = 30;
    my $wd_divider = 10;
    my $disorder_divider = 70;
    my $government_strength_minimum = 60;
    my $government_strength_divider = 40;
    my $random_factor_max = 15;
    
    
    my $disorder = ( ($wd_middle - $wd) / $wd_divider ) +
                   ( $d / $disorder_divider           ) +
                   ( ($government_strength_minimum - $g) / $government_strength_divider ) +
                   $world->random_around_zero($random_factor_max, 100, "Internal disorder random factor for " . $self->name);
    $disorder = int ($disorder * 100) / 100;
    $self->register_event("DISORDER CHANGE: " . $disorder);
    $self->add_internal_disorder($disorder);
}

sub subtract_production
{
    my $self = shift;
    my $which = shift;
    my $production = shift;
    if($which eq 'export')
    {
        $self->production_for_export($self->production_for_export - $production);
    }
    elsif($which eq 'domestic')
    {
        $self->production_for_domestic($self->production_for_domestic - $production);
    }
    
}

sub add_wealth
{
    my $self = shift;
    my $wealth = shift;
    $self->wealth($self->wealth + $wealth);
    $self->wealth(0) if($self->wealth < 0);
}

sub lower_disorder
{
    my $self = shift;
    if($self->production_for_domestic > RESOURCES_FOR_DISORDER)
    {
        $self->subtract_production('domestic', RESOURCES_FOR_DISORDER);
        $self->add_internal_disorder(-1 * DISORDER_REDUCTION);
        $self->register_event("DISORDER LOWERED TO " . $self->internal_disorder);
    }
}

sub add_internal_disorder
{
    my $self = shift;
    my $disorder = shift;
    my $actual_disorder = $self->internal_disorder_status;
    my $new_disorder_data = $self->internal_disorder + $disorder;
    $new_disorder_data = int($new_disorder_data * 100) / 100;
    $self->internal_disorder($new_disorder_data);
    if($self->internal_disorder > 100)
    {
        $self->internal_disorder(100);
    }
    if($self->internal_disorder < 0)
    {
        $self->internal_disorder(0);
    }
    my $new_disorder = $self->internal_disorder_status;
    if($actual_disorder ne $new_disorder)
    {
        $self->register_event("INTERNAL DISORDER LEVEL FROM $actual_disorder TO $new_disorder");
        if($new_disorder eq "Civil war")
        {
            $self->register_event("CIVIL WAR OUTBREAK");
            $self->rebel_provinces(STARTING_REBEL_PROVINCES->[$self->size]);
        }
    }
}

sub internal_disorder_status
{
    my $self = shift;
    my $disorder = $self->internal_disorder;
    if($disorder < INTERNAL_DISORDER_TERRORISM_LIMIT)
    {
        return "Peace";
    }
    elsif($disorder < INTERNAL_DISORDER_INSURGENCE_LIMIT)
    {
        return "Terrorism";
    }
    elsif($disorder < INTERNAL_DISORDER_CIVIL_WAR_LIMIT)
    {
        return "Insurgence";
    }
    else
    {
        return "Civil war";
    }
}

sub fight_civil_war
{
    my $self = shift;
    my $world = shift;
    return undef if($self->internal_disorder_status ne 'Civil war');
    my $government = $world->random(0, 100, "Civil war " . $self->name . ": government fight result");
    my $rebels = $world->random(0, 100, "Civil war " . $self->name . ": rebels fight result");
    $self->register_event("FIGHTING CIVIL WAR");
    if($self->army >= ARMY_UNIT_FOR_INTERNAL_DISORDER)
    {
        $self->add_army(-1 * ARMY_UNIT_FOR_INTERNAL_DISORDER);
        $government += ARMY_HELP_FOR_INTERNAL_DISORDER;
    }
    if($self->government eq 'dictatorship')
    {
        $government += DICTATORSHIP_BONUS_FOR_CIVIL_WAR;
    }
    if($government > $rebels)
    {
        return $self->civil_war_battle('government');
    }
    elsif($rebels > $government)
    {
        return $self->civil_war_battle('rebels');
    }
    else
    {
        return undef;
    }
}

sub civil_war_battle
{
    my $self = shift;
    my $battle_winner = shift;
    if($battle_winner eq 'government')
    {
        $self->rebel_provinces($self->rebel_provinces() - .5);
    }
    elsif($battle_winner eq 'rebels')
    {
        $self->rebel_provinces($self->rebel_provinces() + .5);
    }
    if($self->rebel_provinces == 0)
    {
        $self->internal_disorder(AFTER_CIVIL_WAR_INTERNAL_DISORDER);
        $self->register_event("THE GOVERNMENT WON THE CIVIL WAR");
        return 'government';
    }
    elsif($self->rebel_provinces == PRODUCTION_UNITS->[$self->size])
    {
        $self->internal_disorder(AFTER_CIVIL_WAR_INTERNAL_DISORDER);
        $self->register_event("THE REBELS WON THE CIVIL WAR");
        $self->rebel_provinces(0);
        return 'rebels';
    }
    return undef;
}

sub new_government
{
    my $self = shift;
    my $world = shift;
    $self->government_strength($world->random10(MIN_GOVERNMENT_STRENGTH, MAX_GOVERNMENT_STRENGTH, "Reroll government strength for " . $self->name));
    $world->reroll_diplomacy($self->name);
    $world->reset_treaties($self->name);
    $world->reset_influences($self->name);
    $world->reset_supports($self->name);
    $world->reset_crises($self->name);
    $self->register_event("NEW GOVERNMENT CREATED");
}

sub occupation
{
    my $self = shift;
    my $world = shift;
    $world->reset_treaties($self->name);
    $world->reset_influences($self->name);
    $world->reset_supports($self->name);
    $world->reset_crises($self->name);
}

sub build_troops
{
    my $self = shift;
    my $army_cost = $self->build_troops_cost();
  
    if($self->production_for_export > $army_cost && $self->army < MAX_ARMY_FOR_SIZE->[ $self->size ])
    {
        $self->subtract_production('export', $army_cost);
        $self->add_army(ARMY_UNIT);
        $self->register_event("NEW TROOPS FOR THE ARMY");
    } 
}

sub build_troops_cost
{
    my $self = shift;
    my $army_cost = ARMY_COST;
    if($self->government eq 'dictatorship')
    {
        $army_cost -= DICTATORSHIP_BONUS_FOR_ARMY_CONSTRUCTION;
    }
    return $army_cost;
}

sub add_army
{
    my $self = shift;
    my $army = shift;
    $self->army($self->army + $army);
    if($self->army > MAX_ARMY_FOR_SIZE->[ $self->size ])
    {
        $self->army(MAX_ARMY_FOR_SIZE->[ $self->size ]);
    }
    if($self->army < 0)
    {
        $self->army(0);
    }

}

sub print_attributes
{
    my $self = shift;
    my $out = "";
    $out .= "Area: " . $self->area . "\n";
    $out .= "Export quote: " . $self->export_quote . "\n";
    $out .= "Government strength: " . $self->government_strength . "\n";
    $out .= "Internal situation: " . $self->internal_disorder_status . "\n";
    return $out;
}

sub print
{
    my $self = shift;
    my $out = "";
    $out .= "Name: " . $self->name . "\n";
    $out .= $self->print_attributes();
    $out .= "Events:\n";
    foreach my $year (sort keys %{$self->events})
    {
        $out .= "  $year:\n";
        foreach my $e (@{$self->events->{$year}})
        {
            $out .= "    " . $e ."\n";
        }
    }
    return $out;
}

1;
