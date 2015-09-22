package BalanceOfPower::Role::Mapmaker;

use v5.10;
use strict;
use Moo::Role;

use BalanceOfPower::Relations::Border;
use BalanceOfPower::Relations::RelPack;

has borders => (
    is => 'ro',
    default => sub { BalanceOfPower::Relations::RelPack->new() },
    handles => { add_border => 'add_link',
                 border_exists => 'exists_link',
                 print_borders => 'print_links'
               }
);

requires 'supporter';

sub load_borders
{
    my $self = shift;
    my $bordersfile = shift;
    my $file = shift || $self->data_directory . "/" . $bordersfile;
    open(my $borders, "<", $file) || die $!;;
    for(<$borders>)
    {
        chomp;
        my $border = $_;
        my @nodes = split(/,/, $border);
        if($self->check_nation_name($nodes[0]) && $self->check_nation_name($nodes[1]))
        {
            if($nodes[0] && $nodes[1] && ! $self->border_exists($nodes[0], $nodes[1]))
            {
                my $b = BalanceOfPower::Relations::Border->new(node1 => $nodes[0], node2 => $nodes[1]);
                $self->add_border($b);
            }
        }
        else
        {
            say "WRONG BORDER: $border";
        }
    }
}

sub near_nations
{
    my $self = shift;
    my $nation = shift;
    return grep { $self->near($nation, $_) && $nation ne $_ } @{$self->nation_names};
}
sub print_near_nations
{
    my $self = shift;
    my $nation = shift;
    my $out = "";
    for($self->near_nations($nation))
    {
        $out .= $_ . "\n";
    }
    return $out;
}

sub near
{
    my $self = shift;
    my $nation1 = shift;
    my $nation2 = shift;
    return 1 if($self->border_exists($nation1, $nation2));
    my @supported = $self->supporter($nation1);
    for(@supported)
    {
        my $nation_supported = $_->destination($nation1);
        return 1 if $nation_supported eq $nation2 ||
                    $self->border_exists($nation_supported, $nation2);
    }
    return 0;
}

sub get_group_borders
{
    my $self = shift;
    my $group1 = shift;
    my $group2 = shift;
    my @from = @{ $group1 };
    my @to = @{ $group2 };
    my @out = ();
    foreach my $to_n (@to)
    {
        foreach my $from_n (@from)
        {
            if($self->near($from_n, $to_n))
            {
                push @out, $to_n;
                last;
            }
        }
    }
    return @out;
}




1;
