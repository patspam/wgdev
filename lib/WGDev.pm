package WGDev;
use strict;
use warnings;
use 5.008008;

our $VERSION = '0.4.0';

use File::Spec ();
use Cwd        ();
use Carp qw(croak);

sub new {
    my $class = shift;
    my $self = bless {}, $class;
    my $root;
    my $config;
    if ( $_[0] && -d $_[0] ) {
        ( $root, $config ) = @_;
    }
    else {
        ( $config, $root ) = @_;
    }
    if ($root) {
        $self->root($root);
    }
    if ($config) {
        $self->config_file($config);
    }
    return $self;
}

sub set_environment {
    my $self = shift;
    require Config;
    croak 'WebGUI root not set'
        if !$self->root;
    croak 'WebGUI config file not set'
        if !$self->config_file;
    $self->{orig_env}
        ||= { map { $_ => $ENV{$_} } qw(WEBGUI_ROOT WEBGUI_CONFIG PERL5LIB) };
    ##no critic (RequireLocalizedPunctuationVars)
    $ENV{WEBGUI_ROOT}   = $self->root;
    $ENV{WEBGUI_CONFIG} = $self->config_file;
    $ENV{PERL5LIB}      = join $Config::Config{path_sep}, $self->lib,
        $ENV{PERL5LIB} || ();
    return 1;
}

sub reset_environment {
    my $self     = shift;
    my $orig_env = delete $self->{orig_env};
    return
        if !$orig_env;
    ##no critic (RequireLocalizedPunctuationVars)
    @ENV{ keys %{$orig_env} } = values %{$orig_env};
    return 1;
}

sub root {
    my $self = shift;
    if (@_) {
        my $path = shift;
        if (   -d $path
            && -e File::Spec->catfile( $path, 'etc', 'WebGUI.conf.original' )
            )
        {
            $self->{root} = File::Spec->rel2abs($path);
            $self->{lib} = File::Spec->catdir( $self->{root}, 'lib' );
            unshift @INC, $self->lib;
        }
        else {
            croak "Invalid WebGUI path: $path\n";
        }
    }
    return $self->{root};
}

sub config_file {
    my $self = shift;
    if (@_) {
        my $path = shift;
        if ( -f $path ) {
        }
        elsif (
            $self->root
            && -f (
                my $fullpath
                    = File::Spec->catfile( $self->root, 'etc', $path ) ) )
        {
            $path = $fullpath;
        }
        else {
            croak "Invalid WebGUI config file: $path\n";
        }
        if ( !$self->root ) {
            ##no critic (RequireCheckingReturnValueOfEval)
            eval {
                $self->root(
                    File::Spec->catpath(
                        ( File::Spec->splitpath($path) )[ 0, 1 ],
                        File::Spec->updir
                    ) );
            };
        }
        $self->close_session;
        $self->close_config;
        $self->{config_file} = File::Spec->rel2abs($path);
        delete $self->{config_file_relative};
    }
    return $self->{config_file};
}

sub lib {
    my $self = shift;
    if ( !wantarray ) {
        return $self->{lib};
    }
    my @lib = $self->{lib};
    if ( !$self->{custom_lib} ) {
        my @custom_lib;
        $self->{custom_lib} = \@custom_lib;
        my $custom
            = File::Spec->catfile( $self->root, 'sbin', 'preload.custom' );
        if ( -f $custom && open my $fh, '<', $custom ) {
            while ( my $line = <$fh> ) {
                $line =~ s/[#].*//msx;
                $line =~ s/\A\s+//msx;
                $line =~ s/\s+\z//msx;
                if ( -d $line ) {
                    unshift @custom_lib, $line;
                }
            }
            close $fh or die "Unable to read $custom\: $!\n";
        }
    }
    unshift @lib, @{ $self->{custom_lib} };
    return @lib;
}

sub config {
    my $self = shift;
    croak 'no config file available'
        if !$self->{config_file};
    return $self->{config} ||= do {
        require Config::JSON;
        Config::JSON->new( $self->config_file );
    };
}

sub close_config {
    my $self = shift;
    delete $self->{config};

    # if we're closing the config, we probably want new sessions to pick up
    # changes to the file
    ## no critic (Modules::RequireExplicitInclusion)
    if ( WebGUI::Config->can('clearCache') ) {
        WebGUI::Config->clearCache;
    }
    return 1;
}

sub config_file_relative {
    my $self = shift;
    return $self->{config_file_relative} ||= do {
        my $config_dir
            = Cwd::realpath( File::Spec->catdir( $self->root, 'etc' ) );
        File::Spec->abs2rel( $self->config_file, $config_dir );
    };
}

sub db {
    my $self = shift;
    require WGDev::Database;
    return $self->{db} ||= WGDev::Database->new( $self->config );
}

sub session {
    my $self = shift;
    require WebGUI::Session;
    if ( $self->{session} ) {
        my $dbh = $self->{session}->db->dbh;

        # if the database handle died, close the session
        if ( !$dbh->ping ) {
            delete $self->{asset};
            ( delete $self->{session} )->close;
        }
    }
    return $self->{session} ||= do {
        my $session
            = WebGUI::Session->open( $self->root, $self->config_file_relative,
            undef, undef, $self->{session_id} );
        $self->{session_id} = $session->getId;
        $session;
    };
}

sub close_session {
    my $self = shift;
    if ( $self->{session} ) {    # if we have a cached session
        my $session = $self->session;  # get the session, recreating if needed
        $session->var->end;            # close the session
        $session->close;
        delete $self->{asset};
        delete $self->{session};
    }
    return 1;
}

sub asset {
    my $self = shift;
    require WGDev::Asset;
    return $self->{asset} ||= WGDev::Asset->new( $self->session );
}

sub version {
    my $self = shift;
    require WGDev::Version;
    return $self->{version} ||= WGDev::Version->new( $self->root );
}

sub wgd_config {    ##no critic (ProhibitExcessComplexity)
    my ( $self, $key_list, $value ) = @_;
    my $config = \( $self->{wgd_config} );
    if ( !${$config} ) {
        $config = \( $self->read_wgd_config );
    }
    my @keys;
    if ( ref $key_list && ref $key_list eq 'ARRAY' ) {
        @keys = @{$key_list};
    }
    else {
        @keys = split /[.]/msx, $key_list;
    }

    if ( !${$config} ) {
        $config = \( $self->{wgd_config} = {} );
    }
    while (@keys) {
        my $key     = shift @keys;
        my $numeric = $key ne q{} && $key =~ /^[+]?-?\d*$/msx;
        my $type    = ref ${$config};
        if (   ( !$type && !defined $value )
            || $type eq 'SCALAR'
            || ( $type eq 'ARRAY' && !$numeric ) )
        {
            return;
        }
        elsif ( $type eq 'ARRAY' or ( !$type && $numeric ) ) {
            if ( !$type ) {
                ${$config} = [];
            }
            my ($insert) = $key =~ s/^([+])//msx;
            if ( !defined $value
                && ( $insert || !defined ${$config}->[$key] ) )
            {
                return;
            }
            if ($insert) {
                if ( $key ne q{} ) {
                    if ( $key < 0 ) {
                        $key += @{ ${$config} };
                    }
                    splice @{ ${$config} }, $key, 0, undef;
                }
                else {
                    $key = @{ ${$config} };
                }
            }
            $config = \( ${$config}->[$key] );
        }
        else {
            if ( !$type ) {
                ${$config} = {};
            }
            if ( !defined ${$config}->{$key} && !defined $value ) {
                return;
            }
            $config = \( ${$config}->{$key} );
        }
        if (@keys) {
            next;
        }
        if ($value) {
            return ${$config} = $value;
        }
        return ${$config};
    }
    return;
}

my $json;

sub read_wgd_config {
    my $self = shift;
    for my $config_file ( "$ENV{HOME}/.wgdevcfg", '/etc/wgdevcfg' ) {
        if ( -f $config_file ) {
            my $config;
            open my $fh, '<', $config_file or next;
            my $content = do { local $/ = undef; <$fh> };
            close $fh or next;
            $self->{wgd_config_path} = Cwd::realpath($config_file);
            if ( $content eq q{} ) {
                $config = {};
            }
            else {
                if ( !$json ) {
                    require JSON;
                    $json = JSON->new;
                    $json->utf8;
                    $json->relaxed;
                    $json->canonical;
                    $json->pretty;
                }
                eval { $config = $json->decode($content); } || do {
                    $config = {};
                };
            }
            return $self->{wgd_config} = $config;
        }
    }
    return $self->{wgd_config} = {};
}

sub write_wgd_config {
    my $self        = shift;
    my $config_path = $self->{wgd_config_path};
    if ( !$self->{wgd_config_path} ) {
        $config_path = $self->{wgd_config_path} = $ENV{HOME} . '/.wgdevcfg';
    }
    my $config = $self->{wgd_config} || {};
    if ( !$json ) {
        require JSON;
        $json = JSON->new;
        $json->utf8;
        $json->relaxed;
        $json->canonical;
        $json->pretty;
    }
    my $encoded = $json->encode($config);
    $encoded =~ s/\n?\z/\n/msx;
    open my $fh, '>', $config_path
        or croak "Unable to write to $config_path: $!";
    print {$fh} $encoded;
    close $fh or croak "Unable to write to $config_path: $!";
    return 1;
}

sub my_config {
    my $self = shift;
    my $key  = shift;
    my @keys;
    if ( ref $key && ref $key eq 'ARRAY' ) {
        @keys = @{$key};
    }
    else {
        @keys = split /[.]/msx, $key;
    }
    my $caller = caller;
    my $remove = ( ref $self ) . q{::};
    $caller =~ s/^\Q$remove//msx;
    unshift @keys, map { lcfirst $_ } split /::/msx, $caller;
    return $self->wgd_config( \@keys, @_ );
}

sub yaml_decode {
    _load_yaml_lib();
    goto &yaml_decode;
}

sub yaml_encode {
    _load_yaml_lib();
    goto &yaml_encode;
}

sub _load_yaml_lib {
    ## no critic (ProhibitCascadingIfElse)
    no warnings 'redefine';
    if ( eval { require YAML::XS } ) {
        *yaml_encode = \&YAML::XS::Dump;
        *yaml_decode = \&YAML::XS::Load;
    }
    elsif ( eval { require YAML::Syck } ) {
        *yaml_encode = \&YAML::Syck::Dump;
        *yaml_decode = \&YAML::Syck::Load;
    }
    elsif ( eval { require YAML } ) {
        *yaml_encode = \&YAML::Dump;
        *yaml_decode = \&YAML::Load;
    }
    elsif ( eval { require YAML::Tiny } ) {
        *yaml_encode = \&YAML::Tiny::Dump;
        *yaml_decode = \&YAML::Tiny::Load;
    }
    else {
        *yaml_encode = *yaml_decode = sub {
            die "No YAML library available!\n";
        };
    }
    return;
}

sub DESTROY {
    my $self = shift;
    $self->close_session;
    return;
}

1;

__END__

=head1 NAME

WGDev - WebGUI Developer Utilities

=head1 SYNOPSIS

    use WGDev;

    my $wgd = WGDev->new( $webgui_root, $config_file );

    my $webgui_session = $wgd->session;
    my $webgui_version = $wgd->version->module;

=head1 DESCRIPTION

Performs common actions needed by WebGUI developers, such as recreating their
site from defaults, checking version numbers, exporting packages, and more.

=head1 SUBROUTINES

=head2 C<yaml_encode ( $structure )>

Loads a YAML module if needed and encodes a data structure with it.

=head2 C<yaml_decode ( $yaml_string )>

Loads a YAML module if needed and decodes a data structure with it.

=head1 METHODS

=head2 C<new ( [ $root ], [ $config ] )>

Creates a new WGDev object.  Optionally accepts a WebGUI root path and config
file.  These will be passed on to the C<root> and C<config_file> methods.

=head2 C<root ( [ $webgui_root ] )>

Sets or returns the WebGUI root path the object will be interacting with.  If
the path can't be recognized as a WebGUI root, an error will be thrown.  The
return value will always be an absolute path to the WebGUI root.

=head2 C<config_file ( [ $webgui_config ] )>

Sets or returns the site config file path.  The given path can be relative to
the current directory or to the etc directory in the WebGUI root.  If the
config file is found and the WebGUI root is not yet set, it will set the root
based on the config file path.  If the specified config file can't be found,
an error will be thrown.

=head2 C<config_file_relative>

Returns the config file path relative to the WebGUI config directory.  Useful
for initializing WebGUI sessions, which require the config path to be relative
to that directory.

=head2 C<lib>

In scalar context, returns the WebGUI library path based on the WebGUI root.
In array context, it also includes the library paths specified in the
F<preload.custom> file.

=head2 C<config>

Returns a Config::JSON object based on the file set using C<config_file>.

=head2 C<session>

Returns a WebGUI session initialized using the WebGUI root and config file.

=head2 C<asset>

Returns a L<WGDev::Asset> object for simple asset operations.

=head2 C<db>

Returns a L<WGDev::Database> object for database interaction without starting
a WebGUI session.

=head2 C<version>

Returns a L<WGDev::Version> object for checking the WebGUI version number in
several different places.

=head2 C<close_config>

Closes the link to the WebGUI config file.  Future calls to C<config> will
load a new object based on the file.

=head2 C<close_session>

Closes the WebGUI session.  If the session object has expired or is no longer
valid, it will first be re-opened, then closed properly.

=head2 C<set_environment>

Sets the C<WEBGUI_ROOT>, C<WEBGUI_CONFIG>, and C<PERL5LIB> environment variables
based on C<root>, C<config_file>, and C<lib>.

=head2 C<reset_environment>

Resets the C<WEBGUI_ROOT>, C<WEBGUI_CONFIG>, and C<PERL5LIB> based to what they
were prior to set_environment being called.

=head2 C<wgd_config ( [ $config_param [, $value ] ] )>

Get or set WGDev config file parameters.  Accepts two parameters, the config
directive and optionally the value to set it to.  The config directive is the
path in a data structure specified either as an array reference of keys or a
period separated string of keys.

=head2 C<my_config ( [ $config_param [, $value ] ] )>

Similar to wgd_config, but prefixes the specified path with keys based on the
caller's package.  For example, a package of C<WGDev::Command::Reset> becomes
C<command.reset>.

=head2 C<read_wgd_config>

Reads and parses the WGDev config file into memory.  Will be automatically
called by C<wgd_config> as needed.

=head2 C<write_wgd_config>

Saves the current configuration back to the WGDev config file.

=head1 AUTHOR

Graham Knop <graham@plainblack.com>

=head1 LICENSE

Copyright (c) Graham Knop.

This library is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.

=cut

