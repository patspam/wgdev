package WGDev::Command::Workflow;
use strict;
use warnings;
use 5.008008;

our $VERSION = '0.2.0';

use WGDev::Command::Base;
use Carp;
BEGIN { our @ISA = qw(WGDev::Command::Base) }

sub config_options {
    return qw(
        class=s
        set=s@
        verbose|v
        user=s
    );
}

sub process {
    my $self = shift;
    my $wgd  = $self->wgd;

    my $session = $wgd->session();
    my $class   = $self->option('class');
    my $verbose = $self->option('verbose');
    my $object;
    
    print "$class\n" if $verbose;
    
    if (my $user = $self->option('user')) {
        $object = $self->find_user($user);
        print "Passing in user: @{[$object->username || $object->userId]}\n" if $verbose;
    }
    
    WebGUI::Pluggable::load($class);

    my %data = ( className => $class );
    for my $definition ( reverse @{ $class->definition($session) } ) {
        for my $property ( keys %{ $definition->{properties} } ) {
            if ( !defined $data{$property}
                || $data{$property} eq '' && $definition->{properties}{$property}{defaultValue} )
            {
                $data{$property} = $definition->{properties}{$property}{defaultValue};
            }
        }
    }
    
    my $activity = $class->newByPropertyHashRef( $session, \%data );
    for my $s (@{$self->option('set') || []}) {
        my ($field, $value) = split /=/, $s;
        next unless defined $field && defined $value;
        $activity->{_data}{$field} = $value;
    }
    if ($verbose) {
        print "Activity properties:\n";
        print Data::Dumper::Dumper($activity->{_data});
    }
    
    my $result = $activity->execute($object);
    
    print "Result: $result\n" if $verbose;
    
    return 1;
}

sub find_user {
    my ( $self, $user_spec ) = @_;
    my $session = $self->wgd->session;
    my $user;
    $user = WebGUI::User->new( $session, $user_spec );
    if ( !$user ) {
        $user = WebGUI::User->newByUsername( $session, $user_spec );
    }
    if ( !$user ) {
        $user = WebGUI::User->newByEmail( $session, $user_spec );
    }
    if ( $user && ref $user && $user->isa('WebGUI::User') ) {
        return $user;
    }
    croak "Not able to find user $user_spec";
}

1;

__END__

=head1 NAME

WGDev::Command::Workflow - Test Workflow Activities from the command line

=head1 SYNOPSIS

    wgd workflow --class=WebGUI::Workflow::Activity::RunCommandAsUser --set command=ls --user 1 -v

=head1 DESCRIPTION

Instantiates the given Workflow Activity class (without actually creating a workflow), sets any 
requested properties on the Activity, optionally passes in an object (such as a User) and then
executes the activity. Handy for testing a Workflow Activity outside of Spectre during development

=head1 AUTHOR

Patrick Donelan <pat@patspam.com>

=head1 LICENSE

Copyright (c) Patrick Donelan.  All rights reserved.

This library is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.

=cut
