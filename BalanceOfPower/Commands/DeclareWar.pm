package BalanceOfPower::Commands::DeclareWar;

use Moo;

extends 'BalanceOfPower::Commands::TargetNation';

sub get_available_targets
{
    my $self = shift;
    return $self->world->available_for_war($self->world->player_nation);    
}

1;