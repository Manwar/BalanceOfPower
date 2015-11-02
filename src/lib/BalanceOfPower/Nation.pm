package BalanceOfPower::Nation;

use strict;
use v5.10;

use Moo;
use Array::Utils qw(intersect);

use BalanceOfPower::Utils qw( prev_turn );
use BalanceOfPower::Constants ':all';

with 'BalanceOfPower::Role::Reporter';


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
sub decision
{
    my $self = shift;
    my $world = shift;
    my @advisors;
    if($world->at_war($self->name) || $world->at_civil_war($self->name))
    {
        @advisors = ('military');
    }
    else
    {
        @advisors = ('domestic', 'economy', 'military');
    }
    @advisors = $world->shuffle("Choosing advisor for ".$self->name, @advisors);
    foreach my $a (@advisors)
    {
        my $decision = undef;
        if($a eq 'domestic')
        {
            $decision = $self->domestic_advisor($world);
        }
        elsif($a eq 'economy')
        {
            $decision = $self->economy_advisor($world);
        }
        elsif($a eq 'military')
        {
            $decision = $self->military_advisor($world);
        }
        return $decision if($decision);
    }
    return undef;
}

# Military advisor
#
# DECLARE WAR TO
# MILITARY SUPPORT
# RECALL MILITARY SUPPORT
# BUILD TROOPS

sub military_advisor
{
    my $self = shift;
    my $world = shift;
    if(! $world->war_busy($self->name))
    {
        #WAR ATTEMPT
        my @crises = $world->get_crises($self->name);
        if(@crises > 0)
        {
            foreach my $c ($world->shuffle("Mixing crisis for war for " . $self->name, @crises))
            {
                my $enemy = $world->get_nation($c->destination($self->name));
                next if $world->war_busy($enemy->name);
                if($world->in_military_range($self->name, $enemy->name))
                {
                    if($self->good_prey($enemy, $world, $c->crisis_level))
                    {
                        return $self->name . ": DECLARE WAR TO " . $enemy->name;
                    }
                    else
                    {
                        if($self->production_for_export >= AID_INSURGENTS_COST)
                        {
                            return $self->name . ": AID INSURGENTS IN " . $enemy->name;
                        }
                    }
                }
                else
                {
                    if($self->army >= MIN_ARMY_TO_EXPORT)
                    {
                        my @friends = $world->get_friends($self->name);                        
                        for(@friends)
                        {
                            if($world->border_exists($_, $enemy->name))
                            {
                                return $self->name . ": MILITARY SUPPORT " . $_;
                            }
                        }
                    }
                }
            }
        }
        #MILITARY SUPPORT
        if($self->army >= MIN_ARMY_TO_EXPORT)
        {
            my @friends = $world->shuffle("Choosing friend to support for " . $self->name, $world->get_friends($self->name));
            my $f = $friends[0];
            if($world->get_nation($f)->accept_military_support($self->name, $world))
            {
                return $self->name . ": MILITARY SUPPORT " . $f;
            }
        }
    }
    if($self->army <= ARMY_TO_RECALL_SUPPORT)
    {
        my @supports = $world->supporter($self->name);
        if(@supports > 0)
        {
            @supports = $world->shuffle("Choosing support to recall", @supports);
            return $self->name . ": RECALL MILITARY SUPPORT " . $supports[0]->destination($self->name);
        }
    }
    if($self->army < MAX_ARMY_FOR_SIZE->[ $self->size ])
    {
        if($self->army < MINIMUM_ARMY_LIMIT)
        {
            return $self->name . ": BUILD TROOPS";
        }
        elsif($self->army < MEDIUM_ARMY_LIMIT)
        {
            if($self->production_for_export > MEDIUM_ARMY_BUDGET)
            {
                return $self->name . ": BUILD TROOPS";
            }
        }
        elsif($self->army < MAX_ARMY_LIMIT)
        {
            if($self->production_for_export > MAX_ARMY_BUDGET)
            {
                return $self->name . ": BUILD TROOPS";
            }
        }
    }
}
sub accept_military_support
{
    my $self = shift;
    my $other = shift;
    my $world = shift;
    return 0 if($world->already_in_military_support($self->name));
    return $self->army < ARMY_TO_ACCEPT_MILITARY_SUPPORT;
}

sub good_prey
{
    my $self = shift;
    my $enemy = shift;
    my $world = shift;
    my $level = shift;
    if($self->army < MIN_ARMY_FOR_WAR)
    {
        return 0;
    }
    my $war_points = 0;

    #ARMY EVALUATION
    my $army_ratio;
    if($enemy->army > 0)
    {
        $army_ratio = int($self->army / $enemy->army);
    }
    else
    {
        $army_ratio = 3;
    }
    if($army_ratio < 1)
    {
        my $reverse_army_ratio = $enemy->army / $self->army;
        if($reverse_army_ratio > MIN_INFERIOR_ARMY_RATIO_FOR_WAR)
        {
            return 0;
        }
        else
        {
            $army_ratio = -1;
        }
    }
    $war_points += $army_ratio;

    #INTERNAL EVALUATION
    if($self->internal_disorder_status eq 'Peace')
    {
        $war_points += 1;
    }
    elsif($self->internal_disorder_status eq 'Terrorism')
    {
        $war_points += 0;
    }
    elsif($self->internal_disorder_status eq 'Insurgence')
    {
        $war_points += -1;
    }

    #WEALTH EVALUATION
    my $wealth = $world->get_statistics_value(prev_turn($self->current_year), $self->name, 'wealth');
    my $enemy_wealth = $world->get_statistics_value(prev_turn($self->current_year), $enemy->name, 'wealth');
    if($wealth && $enemy_wealth)
    {
        $war_points += 1 if($enemy_wealth > $wealth);
    }
    else
    {
        $war_points += 1;
    }

                    
    #COALITION EVALUATION
    if($world->empire($self->name) && $world->empire($enemy->name) && $world->empire($self->name) > $world->empire($enemy->name))
    {
        $war_points += 1;
    }

    if($war_points + $level >= 4)
    {
        return 1;
    }
    else
    {
        return 0;
    }
}

# Domestic advisor
#
# LOWER DISORDER
# BOOST PRODUCTION
# TREATY NAG

sub domestic_advisor
{
    my $self = shift;
    my $world = shift;
    if($self->internal_disorder > WORRYING_LIMIT && $self->production_for_domestic > DOMESTIC_BUDGET)
    {
        return $self->name . ": LOWER DISORDER";
    }
    elsif($self->production < EMERGENCY_PRODUCTION_LIMIT)
    {
        return $self->name . ": BOOST PRODUCTION";
    }
    elsif($self->prestige >= TREATY_PRESTIGE_COST)
    {
        #Scanning neighbors
        my @near = $world->near_nations($self->name, 1);
        my @friends = $world->get_nations_with_status($self->name, ['NEUTRAL', 'FRIENDSHIP', 'ALLIANCE']);
        my @friendly_neighbors = $world->shuffle("Mixing neighbors to choose about NAG treaty", intersect(@near, @friends));
        my @ordered_friendly_neighbors = ();
        for(@friendly_neighbors)
        {
            my $n = $_;
            if(! $world->exists_treaty($self->name, $n))
            {
                my @supporter = $world->supported($n);
                if(@supporter > 0)
                {
                    my $supporter_nation = $supporter[0]->node1;
                    if($supporter_nation eq $self->name)
                    {
                        #I'm the supporter of this nation!
                        push @ordered_friendly_neighbors, { nation => $n,
                                                            interest => 0 };
                    }
                    else
                    {
                        if($world->crisis_exists($self->name, $supporter_nation))
                        {
                            push @ordered_friendly_neighbors, { nation => $n,
                                                                interest => 100 };
                        }
                        elsif($world->diplomacy_status($self->name, $supporter_nation) eq 'HATE')
                        {
                            push @ordered_friendly_neighbors, { nation => $n,
                                                            interest => 10 };
                        }
                        else
                        {
                            push @ordered_friendly_neighbors, { nation => $n,
                                                                interest => 2 };
                        }
                    }
                }
                else
                {
                    push @ordered_friendly_neighbors, { nation => $n,
                                                        interest => 1 };
                }
            }
        }
        if(@ordered_friendly_neighbors > 0)
        {
            @ordered_friendly_neighbors = sort { $b->{interest} <=> $a->{interest} } @ordered_friendly_neighbors;
            return $self->name . ": TREATY NAG WITH " . $ordered_friendly_neighbors[0]->{nation};
        }
        else
        {
            #Scanning crises
            my @crises = $world->get_crises($self->name);
            if(@crises > 0)
            {
                foreach my $c ($world->shuffle("Mixing crisis for war for " . $self->name, @crises))
                {
                    #NAG with enemy supporter
                    my $enemy = $c->destination($self->name);
                    my @supporter = $world->supported($enemy);
                    if(@supporter > 0)
                    {
                        my $supporter_nation = $supporter[0]->node1;
                        if($supporter_nation ne $self->name &&
                           $world->diplomacy_status($self->name, $supporter_nation) ne 'HATE' &&
                           ! $world->exists_treaty($self->name, $supporter_nation))
                        {
                            return $self->name . ": TREATY NAG WITH " . $supporter_nation;
                        } 
                    }
                    #NAG with enemy ally
                    my @allies = $world->get_allies($enemy);
                    for($world->shuffle("Mixing allies of enemy for a NAG", @allies))
                    {
                        my $all = $_->destination($enemy);
                        if($all ne $self->name &&
                           $world->diplomacy_status($self->name, $all) ne 'HATE' &&
                           ! $world->exists_treaty($self->name, $all))
                        {
                            return $self->name . ": TREATY NAG WITH " . $all;
                        } 
                    }
                }
            }
            else
            {
                return undef;
            }
        }
    }
    else
    {
        return undef;
    }
}

# Economy advisor
#
# DELETE TRADEROUTE
# ADD ROUTE
# TREATY COM

sub economy_advisor
{
    my $self = shift;
    my $world = shift;
    my $prev_year = prev_turn($self->current_year);
    my @trade_ok = $self->get_events("TRADE OK", $prev_year);
    if($self->prestige >= TREATY_PRESTIGE_COST && @trade_ok > 0)
    {
        for(@trade_ok)
        {
            my $route = $_;
            $route =~ s/^TRADE OK //;
            $route =~ s/ \[.*$//;
            my $status = $world->diplomacy_status($self->name, $route);
            if(! $world->exists_treaty($self->name, $route) && $status ne 'HATE')
            {
                return $self->name . ": TREATY COM WITH " . $route;
            }
        }
    }
    my @trade_ko = $self->get_events("TRADE KO", $prev_year);
    if(@trade_ko > 1)
    {
        #my $to_delete = $trade_ko[$#trade_ko];
        #$to_delete =~ s/TRADE KO //;
        #return $self->name . ": DELETE TRADEROUTE " . $self->name . "->" . $to_delete;
        for(@trade_ko)
        {
            my $to_delete = $_;
            $to_delete =~ s/TRADE KO //;
            if(! $world->exists_treaty_by_type($self->name, $to_delete, 'commercial'))
            {
                return $self->name . ": DELETE TRADEROUTE " . $self->name . "->" . $to_delete;   
            }
        }
    }
    elsif(@trade_ko == 1)
    {
        my @older_trade_ko = $self->get_events("TRADE KO", prev_turn($prev_year));
        if(@older_trade_ko > 0)
        {
            my $to_delete = $trade_ko[$#trade_ko];
            $to_delete =~ s/TRADE KO //;
            if(! $world->exists_treaty_by_type($self->name, $to_delete, 'commercial'))
            {
                return $self->name . ": DELETE TRADEROUTE " . $self->name . "->" . $to_delete;
            }
        }
    }
    else
    {
        my @remains = $self->get_events("REMAIN", $prev_year);
        my @deleted = $self->get_events("TRADEROUTE DELETED", $prev_year);
        my @boost = $self->get_events("BOOST OF PRODUCTION", $prev_year);
        if(@remains > 0 && @deleted == 0 && @boost == 0)
        {
            my $rem = $remains[0];
            $rem =~ m/^REMAIN (.*)$/;
            my $remaining = $1;
            if($remaining >= TRADING_QUOTE && $self->production_for_export > TRADINGROUTE_COST)
            {
                return $self->name . ": ADD ROUTE";
            }
        }
    }
    return undef;
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
