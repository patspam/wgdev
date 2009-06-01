package WGDev::Command::Dist;
use strict;
use warnings;
use 5.008008;

our $VERSION = '0.1.0';

use WGDev::Command::Base;
BEGIN { our @ISA = qw(WGDev::Command::Base) }

use File::Spec ();

sub process {
    my $self = shift;
    my $wgd  = $self->wgd;
    require File::Temp;
    require File::Copy;
    require Cwd;

    my ( $version, $status ) = $wgd->version->module;
    my $build_root   = File::Temp->newdir;
    my $build_webgui = File::Spec->catdir( $build_root, 'WebGUI' );
    my $build_docs   = File::Spec->catdir( $build_root, 'api' );
    my $cwd          = Cwd::cwd();

    mkdir $build_webgui;
    $self->export_files($build_webgui);
    if ( !fork ) {
        chdir $build_root;
        exec 'tar', 'czf',
            File::Spec->catfile( $cwd, "webgui-$version-$status.tar.gz" ),
            'WebGUI';
    }
    wait;

    mkdir $build_docs;
    $self->generate_docs($build_docs);
    if ( !fork ) {
        chdir $build_root;
        exec 'tar', 'czf',
            File::Spec->catfile( $cwd, "webgui-api-$version-$status.tar.gz" ),
            'api';
    }
    wait;
    return 1;
}

sub export_files {
    my $self    = shift;
    my $to_root = shift;
    my $from    = $self->wgd->root;

    if ( -e File::Spec->catdir( $from, '.git' ) ) {
        system 'git', '--git-dir=' . File::Spec->catdir( $from, '.git' ),
            'checkout-index', '-a', '--prefix=' . $to_root . q{/};
    }
    elsif ( -e File::Spec->catdir( $from, '.svn' ) ) {
        system 'svn', 'export', $from, $to_root;
    }
    else {
        system 'cp', '-r', $from, $to_root;
    }

    for my $file (
        [ 'docs', 'previousVersion.sql' ],
        [ 'etc',  '*.conf' ],
        [ 'sbin', 'preload.custom' ],
        [ 'sbin', 'preload.exclude' ] )
    {
        my $file_path = File::Spec->catfile( $to_root, @{$file} );
        for my $file ( glob $file_path ) {
            unlink $file;
        }
    }
    return $to_root;
}

sub generate_docs {
    my $self    = shift;
    my $to_root = shift;
    my $from    = $self->wgd->root;
    require File::Find;
    require File::Path;
    require Pod::Html;
    require File::Temp;
    my $code_dir = File::Spec->catdir( $from, 'lib', 'WebGUI' );
    my $temp_dir = File::Temp->newdir;
    File::Find::find( {
            no_chdir => 1,
            wanted   => sub {
                no warnings 'once';
                my $code_file = $File::Find::name;
                return
                    if -d $code_file;
                my $doc_file = $code_file;
                return
                    if $doc_file =~ /\b\QOperation.pm\E$/msx;
                return
                    if $doc_file !~ s/\Q.pm\E$/.html/msx;
                $doc_file = File::Spec->rel2abs(
                    File::Spec->abs2rel( $doc_file, $code_dir ), $to_root );
                my $directory = File::Spec->catpath(
                    ( File::Spec->splitpath($doc_file) )[ 0, 1 ] );
                File::Path::mkpath($directory);
                Pod::Html::pod2html(
                    '--quiet',
                    '--noindex',
                    '--infile=' . $code_file,
                    '--outfile=' . $doc_file,
                    '--cachedir=' . $temp_dir,
                );
            },
        },
        $code_dir
    );
    return $to_root;
}

1;

__END__

=head1 NAME

WGDev::Command::Dist - Create a distribution file for WebGUI

=head1 SYNOPSIS

    wgd dist [-c] [-d]

=head1 DESCRIPTION

Generates distribution files containing WebGUI or the WebGUI API.

=head1 OPTIONS

By default, generates both a code and API documentation package.

=over 8

=item C<-c> C<--code>

Generates a code distribution

=item C<-d> C<--documentation>

Generates an API documentation distribution

=back

=head1 METHODS

=head2 C<export_files ( $directory )>

Exports the WebGUI root directory, excluding common site specific files, to
the specified directory.

=head2 C<generate_docs ( $directory )>

Generate API documentation for WebGUI using Pod::Html in the specified
directory.

=head1 AUTHOR

Graham Knop <graham@plainblack.com>

=head1 LICENSE

Copyright (c) Graham Knop.  All rights reserved.

This library is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.

=cut

