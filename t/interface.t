use BalanceOfPower::World;
use BalanceOfPower::Commands;
use BalanceOfPower::Relations::Alliance;
use BalanceOfPower::Relations::Crisis;
use BalanceOfPower::Relations::War;
use Test::More;

#Initialization of test scenario
my @nation_names = ("Italy", "France", "United Kingdom", "Russia", 
                    "Germany"); 
my $first_year = 1970;
my $world = BalanceOfPower::World->new( first_year => $first_year );
$world->init_random(\@nation_names, { alliances => 0});
#Stubbed data

$world->get_nation("Italy")->army(15);
$world->get_nation("France")->army(15);
$world->add_alliance(BalanceOfPower::Relations::Alliance->new( node1 => 'Italy', node2 => 'Russia' ));
$world->add_crisis(BalanceOfPower::Relations::Crisis->new( node1 => 'Italy', node2 => 'France' ));
$world->add_war(BalanceOfPower::Relations::War->new(node1 => 'Italy', 
                                                    node2 => 'France',
                                                    attack_leader => 'Italy',
                                                    war_id => 0000000,
                                                    node1_faction => 0,
                                                    node2_faction => 1));

$world->autoplay(1);
$world->elaborate_turn("1970/1");
$world->autoplay(0);

#Initialization of commands
my $commands = BalanceOfPower::Commands->new( world => $world );
$commands->init();
$commands->init_game(1);
my $result;

#Generic commands
foreach my $c ( ("years", "commands", "orders", "wars", "crises", "alliances", "situation") )
{
    $commands->query($c);
    $result = $commands->report_commands();
    is($result->{status}, 1, "Command elaborated: $c");
}

#Nation configured
$commands->query('Italy');
$result = $commands->report_commands();
is($result->{status}, 1, "Command elaborated: Italy");

#Commands for nation
foreach my $c ( ("borders", "relations", "events", "status", "history") )
{
    $commands->query($c);
    $result = $commands->report_commands();
    is($result->{status}, 1, "Command elaborated: $c");
}

#Year command
$commands->query("1970/1");
$result = $commands->report_commands();
is($result->{status}, 1, "Command elaborated: 1970/1");

$commands->query('clear');
$result = $commands->report_commands();
is($result->{status}, 1, "Command elaborated: clear");

$commands->query("1970/1");
$result = $commands->report_commands();
is($result->{status}, 1, "Command elaborated: 1970/1");

$commands->query("turn");
$result = $commands->turn_command();
is($result->{status}, 1, "Command elaborated: turn");

$commands->query("BUILD TROOPS");
$result = $commands->orders();
is($result->{status}, 1, "Command elaborated: BUILD TROOPS");






#$result = $commands->orders();
#$result = $commands->turn_command();

done_testing;

