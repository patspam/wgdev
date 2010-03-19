package WGDev::Command::Flux;
use strict;
use warnings;
use 5.008008;

our $VERSION = '0.0.1';

use WGDev::Command::Base::Verbosity;
BEGIN { our @ISA = qw(WGDev::Command::Base::Verbosity) }

sub config_options {
    return qw(
        enable
        force
        demo
    );
}

sub process {
    my $self    = shift;
    my $wgd     = $self->wgd;
    my $session = $wgd->session;

    if ( $self->option('enable') ) {
        $self->enable_flux( { force => $self->option('force') } );
    }

    if ( $self->option('demo') ) {
        $self->create_demo_data;
    }

    return 1;
}

sub enable_flux {
    my $self    = shift;
    my $options   = shift;
    my $wgd     = $self->wgd;
    my $session = $wgd->session;
    
    if ( !$options->{force} && $session->db->quickScalar('select count(*) from settings where name = "fluxEnabled"')) {
        $self->report("Looks like Flux is already enabled, use --force if you really want to re-apply changes\n");
        return;
    }

    my $quiet = $self->verbosity < 1;
    
    require EnableFlux;
    EnableFlux->apply($session, $quiet);

    $self->report( $wgd->config_file_relative . " was modified so remember to restart modperl.\n" );
}

sub create_demo_data {
    my $self = shift;
    $self->report("Populating site with Flux demo data.. ");
    $self->wgd->session->db->write('delete from fluxRule');
    $self->wgd->session->db->write('delete from fluxExpression');
    $self->wgd->session->db->write('delete from fluxRuleUserData');
    $self->wgd->session->db->write(
        q~
INSERT INTO `fluxRule` (`fluxRuleId`, `name`, `sequenceNumber`, `sticky`, `onRuleFirstTrueWorkflowId`, `onRuleFirstFalseWorkflowId`, `onAccessFirstTrueWorkflowId`, `onAccessFirstFalseWorkflowId`, `onAccessTrueWorkflowId`, `onAccessFalseWorkflowId`, `combinedExpression`) VALUES ('2wKj6EkpLrmU1f6ZVfxzOA','Dependent Rule',2,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL),('M8EjDc89Q8iqBYb4UTRalA','Simple Rule',1,0,NULL,NULL,NULL,NULL,NULL,NULL,'not e1 or e2'),('Yztbug94AbqQkOKhyOT4NQ','Yet Another Rule',3,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL),('NgRW4dh2sDSNEwJPGCtWBg','My empty Rule',4,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL),('VVGkA5gBRlNYd6DrFV5anQ','Another Rule',5,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL)
~
    );
    $self->wgd->session->db->write(
        q~
INSERT INTO `fluxExpression` (`fluxExpressionId`, `fluxRuleId`, `name`, `sequenceNumber`, `operand1`, `operand1Args`, `operand1AssetId`, `operand1Modifier`, `operand1ModifierArgs`, `operand2`, `operand2Args`, `operand2AssetId`, `operand2Modifier`, `operand2ModifierArgs`, `operator`) VALUES ('z3ddMvVUkGx07FeblgFWuw','M8EjDc89Q8iqBYb4UTRalA','Test First Thing',1,'TextValue','{\"value\":  \"test value\"}',NULL,NULL,NULL,'TextValue','{\"value\":  \"test value\"}',NULL,NULL,NULL,'IsEqualTo'),('YiQToMcxB7RUYvmt3CSS-Q','M8EjDc89Q8iqBYb4UTRalA','Test Second Thing',2,'TextValue','{\"value\":  \"boring dry everyday value\"}',NULL,NULL,NULL,'TextValue','{\"value\":  \"super lucky crazy value\"}',NULL,NULL,NULL,'IsEqualTo'),('jNDjhNzuqxinj3r2JG7lXQ','2wKj6EkpLrmU1f6ZVfxzOA','Check Simple Rule',1,'FluxRule','{\"fluxRuleId\":  \"M8EjDc89Q8iqBYb4UTRalA\"}',NULL,NULL,NULL,'TruthValue','{\"value\":  \"1\"}',NULL,NULL,NULL,'IsEqualTo'),('s8wVvTYZyjBt7JqUOs4Urw','2wKj6EkpLrmU1f6ZVfxzOA','Test Something Else',2,'TextValue','{\"value\":  \"test value\"}',NULL,NULL,NULL,'TextValue','{\"value\":  \"test value\"}',NULL,NULL,NULL,'IsEqualTo'),('j9XB0vivxoHYSjuIDIRAEA','Yztbug94AbqQkOKhyOT4NQ','Check Simple Rule',1,'FluxRule','{\"fluxRuleId\":  \"M8EjDc89Q8iqBYb4UTRalA\"}',NULL,NULL,NULL,'TruthValue','{\"value\":  \"1\"}',NULL,NULL,NULL,'IsEqualTo'),('9l9E97tyeuN4HovVDEsKPw','Yztbug94AbqQkOKhyOT4NQ','Check Dependent Rule',2,'FluxRule','{\"fluxRuleId\":  \"2wKj6EkpLrmU1f6ZVfxzOA\"}',NULL,NULL,NULL,'TruthValue','{\"value\":  \"1\"}',NULL,NULL,NULL,'IsEqualTo'),('m5maTmnA55JQW1N-_sOwLg','VVGkA5gBRlNYd6DrFV5anQ','Check the empty Rule',1,'TruthValue','{\"value\":  \"1\"}',NULL,NULL,NULL,'FluxRule','{\"fluxRuleId\":  \"NgRW4dh2sDSNEwJPGCtWBg\"}',NULL,NULL,NULL,'IsEqualTo');
~
    );
    $self->wgd->session->setting->set( 'fluxEnabled', 1 );
    $self->report("DONE\n");
}

1;

__END__

=head1 NAME

WGDev::Command::Flux - Flux commands

=head1 SYNOPSIS

    wgd Flux [--enable] [--force] [--demo]

=head1 DESCRIPTION

Enable Flux for a site.

=head1 OPTIONS

=over 8

=item B<--enable>

Enable Flux. Does nothing if it detects that Flux is already enabled.

=item B<--force>

Force enable action through even if Flux is already enabled.

=item B<--demo>

Populate site with demo Flux data.

=back

=head1 AUTHOR

Patrick Donelan <pat@patspam.com>

=head1 LICENSE

Copyright (c) Patrick Donelan.  All rights reserved.

This library is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.

=cut

