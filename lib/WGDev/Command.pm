package WGDev::Command;
use strict;
use warnings;
use 5.008008;

our $VERSION = '0.2.1';

use Getopt::Long ();
use File::Spec   ();
use Cwd          ();
use Carp qw(croak);
##no critic (RequireCarping)

sub run {
    my $class = shift;
    local @ARGV = @_;
    Getopt::Long::Configure(
        qw(default gnu_getopt pass_through no_auto_abbrev));
    Getopt::Long::GetOptions(
        'h|?|help'      => \( my $opt_help ),
        'V|ver|version' => \( my $opt_version ),

        'F|config-file=s' => \( my $opt_config ),
        'R|webgui-root=s' => \( my $opt_root ),
    ) || warn $class->usage(0) && exit 1;
    my @params = @ARGV;

    my $command_name = shift @params;

    my $command_module = get_command_module($command_name);
    if ( $command_name && !$command_module ) {
        my $command_exec = _find_cmd_exec($command_name);
        if ($command_exec) {
            require WGDev;
            my $wgd = $class->guess_webgui_paths( WGDev->new, $opt_root,
                $opt_config );
            $wgd->set_environment;
            exec {$command_exec} $command_exec, $opt_help ? '--help' : (),
                $opt_version ? '--version' : (), @_;
        }
        else {
            warn $class->usage(
                message          => "Can't find command $command_name!\n",
                include_cmd_list => 1,
                verbosity        => 0,
            );
            exit 2;
        }
    }

    if ($opt_version) {
        $class->report_version( $command_name, $command_module );
    }
    elsif ($opt_help) {
        $class->report_help( $command_name, $command_module );
    }
    elsif ( !$command_name ) {
        warn $class->usage(
            message          => "No command specified!\n",
            include_cmd_list => 1,
            verbosity        => 1,
        );
        exit 1;
    }
    else {
        require WGDev;
        my $wgd = $class->guess_webgui_paths( WGDev->new, $opt_root,
            $opt_config );
        if (
            !eval {
                my $command = $command_module->new($wgd);
                $command->run(@params);
                1;
            } )
        {
            warn $@;
            exit 1;
        }
    }
    exit;
}

sub guess_webgui_paths {
    my ( $class, $wgd, $webgui_root, $webgui_config ) = @_;
    $webgui_root ||= $ENV{WEBGUI_ROOT} || $wgd->my_config('webgui_root');
    $webgui_config ||= $ENV{WEBGUI_CONFIG}
        || $wgd->my_config('webgui_config');

    # first we need to find the webgui root

    if ($webgui_root) {
        $wgd->root($webgui_root);
    }
    if ($webgui_config) {
        my $can_set_config = eval { $wgd->config_file($webgui_config); 1; };

        # if a config file and root were specified and they didn't work, error
        if ( $webgui_root && !$can_set_config ) {
            die $@;
        }
        if ( $can_set_config && $wgd->root ) {
            return $wgd;
        }
    }

    if ( !$wgd->root ) {
        my $dir = Cwd::getcwd();
        while (1) {
            if ( -e File::Spec->catfile( $dir, 'etc', 'WebGUI.conf.original' )
                )
            {
                $wgd->root($dir);
                last;
            }
            my $parent = Cwd::realpath(
                File::Spec->catdir( $dir, File::Spec->updir ) );
            croak "Unable to find WebGUI root directory!\n"
                if $dir eq $parent;
            $dir = $parent;
        }
        if ($webgui_config) {
            $wgd->config_file($webgui_config);
            return $wgd;
        }
    }
    if ( opendir my $dh, File::Spec->catdir( $wgd->root, 'etc' ) ) {
        my @configs = readdir $dh;
        closedir $dh
            or croak "Unable to close directory handle: $!";
        @configs
            = grep { /\Q.conf\E$/msx && !/^(?:spectre|log)\Q.conf\E$/msx }
            @configs;
        if ( @configs == 1 ) {
            $wgd->config_file( $configs[0] );
            return $wgd;
        }
    }
    croak "Unable to find WebGUI config file!\n";
}

sub report_version {
    my ( $class, $name, $module ) = @_;
    if ( ref $class ) {
        $class = ref $class;
    }
    print "$class version " . $class->VERSION;
    if ($module) {
        print " - $module version " . $module->VERSION;
    }
    print "\n";
    return 1;
}

sub report_help {
    my ( $class, $name, $module ) = @_;
    if ( ref $class ) {
        $class = ref $class;
    }
    if ($module) {
        if ( $module->can('usage') ) {
            print $module->usage;
        }
        else {
            warn "No documentation for $name command.\n";
        }
    }
    else {
        print $class->usage(
            verbosity        => 2,
            include_cmd_list => 1,
        );
    }
    return 1;
}

sub get_command_module {
    my $command_name = shift;
    if ( $command_name && $command_name =~ /^[-\w]+$/mxs ) {
        my $module = command_to_module($command_name);
        ( my $module_file = "$module.pm" ) =~ s{::}{/}mxsg;
        if (   eval { require $module_file; 1 }
            && $module->can('run')
            && $module->can('is_runnable')
            && $module->is_runnable )
        {
            return $module;
        }
    }
    return;
}

sub command_to_module {
    my $command = shift;
    my $module = join q{::}, __PACKAGE__, map {ucfirst} split /-/msx,
        $command;
    return $module;
}

sub _find_cmd_exec {
    my ( $command_name, $root, $config ) = @_;
    if ($command_name) {
        for my $path ( File::Spec->path ) {
            my $execpath = File::Spec->catfile( $path, "wgd-$command_name" );
            if ( -x $execpath ) {
                return $execpath;
            }
        }
    }
    return;
}

sub usage {
    my $class = shift;
    my %options = ( @_ % 2 == 0 ) ? @_ : ( verbosity => shift );

    require WGDev::Help;
    my $message = q{};
    if ( $options{message} ) {
        $message .= $options{message};
    }
    $message .= WGDev::Help::package_usage( $class, $options{verbosity} );

    if ( $options{include_cmd_list} ) {
        $message .= "SUBCOMMANDS\n";
        for my $command ( $class->command_list ) {
            $message .= "    $command\n";
        }
        $message .= "\n";
    }
    return $message;
}

sub command_list {
    my $class = shift;
    my %commands;
    ( my $fn_prefix = $class ) =~ s{::}{/}msxg;

    require File::Find;
    my %lib_check;
    for my $inc_path (@INC) {
        ##no critic (ProhibitParensWithBuiltins)
        my $command_root
            = File::Spec->catdir( $inc_path, split( /::/msx, $class ) );
        next
            if !-d $command_root;
        my $find_callback = sub {
            return
                if !/\Q.pm\E$/msx;

            no warnings 'once';
            my $lib_path
                = File::Spec->abs2rel( $File::Find::name, $inc_path );
            $lib_check{$lib_path} = 1;
        };
        File::Find::find( { no_chdir => 1, wanted => $find_callback },
            $command_root );
    }
    for my $module ( grep {m{^$fn_prefix/}msx} keys %INC ) {
        $lib_check{$module} = 1;
    }
    for my $module ( keys %lib_check ) {
        my $package = $module;
        $package =~ s/\Q.pm\E$//msx;
        $package = join q{::}, File::Spec->splitdir($package);
        if (
            eval {
                require $module;
                $package->can('run')
                    && $package->can('is_runnable')
                    && $package->is_runnable;
            } )
        {
            ( my $command = $package ) =~ s/^\Q$class\E:://msx;
            $command = join q{-}, map {lcfirst} split m{::}msx, $command;
            $commands{$command} = 1;
        }
    }

    for my $command ( map { glob File::Spec->catfile( $_, 'wgd-*' ) }
        File::Spec->path )
    {
        next
            if !-x $command;
        my $file = ( File::Spec->splitpath($command) )[2];
        $file =~ s/^wgd-//msx;
        $commands{$file} = 1;
    }
    my @commands = sort keys %commands;
    return @commands;
}

1;

__END__

=head1 NAME

WGDev::Command - Run WGDev commands

=head1 SYNOPSIS

    wgd [arguments] <subcommand> [subcommand arguments]

=head1 DESCRIPTION

Runs sub-commands from the C<WGDev::Command> namespace, or standalone scripts starting with F<wgd->

=head1 OPTIONS

=over 8

=item C<-h> C<-?> C<--help>

Display help for any command.

=item C<-V> C<--version>

Display version information

=item C<-F> C<--config-file>

Specify WebGUI config file to use.  Can be absolute, relative to the current
directory, or relative to WebGUI's config directory.  If not specified, it
will try to use the C<WEBGUI_CONFIG> environment variable.  If that is not
set and there is only one config file in WebGUI's config directory, that file
will be used.

=item C<-R> C<--webgui-root>

Specify WebGUI's root directory.  Can be absolute or relative.  If not
specified, first the C<WEBGUI_ROOT> environment variable will be checked,
then will search upward from the current path for a WebGUI installation.

=item C<< <subcommand> >>

Sub-command to run or get help for.

=back

=head1 SUBROUTINES

=head2 C<command_to_module ( $command )>

Converts a command into the module that would implement it.  Returns
that module name.

=head2 C<get_command_module ( $command )>

Converts the command to a module, then attempts to load that module.
If the module loads successfully, implements the C<run> and
C<is_runnable> methods, and C<is_runnable> returns true, returns
the module.  If not, returns C<undef>.

=head1 METHODS

=head2 C<run ( @arguments )>

Runs C<wgd>, processing the arguments specified and running a sub-command if possible.

=head2 C<usage ( %options )>

Returns usage information for C<wgd>.  The options hash specifies additional options:

=head3 C<verbosity>

The verbosity level of the usage information.  This is passed on
to L<WGDev::Help::package_usage|WGDev::Help/package_usage>.

=head3 C<message>

An additional message to include before the usage information.

=head3 C<include_cmd_list>

Include the list of available sub-commands with the usage information.

=head2 C<command_list>

Searches for available sub-commands and returns them as an array.  This list includes available Perl modules that pass the L</get_command_module> check and executable files beginning with F<wgd->.

=head2 C<guess_webgui_paths ( $wgd, [$webgui_root], [$webgui_config] )>

Attempts to detect the paths to use for the WebGUI root and config
file.  Initializes the specified $wgd object.  If specified, attempts
to use the specified paths first.  If not specified, first checks
the environment variables C<WEBGUI_ROOT> and C<WEBGUI_CONFIG>.
Next, attempts to search upward from the current path to find the
WebGUI root.  If a WebGUI root has been found but not a config file,
checks for available config files.  If only one is available, it
is used as the config file.

=head2 C<report_help ( [$command, $module] )>

Shows help information for C<wgd> or a sub-command.  If a command
and module is specified, attempts to call C<usage> on the module
or displays an error.  Otherwise, displays help information for
C<wgd>.

=head2 C<report_version ( [$command, $module] )>

Reports version information about C<wgd>.  If specified, also
includes version information about a sub-command.

=head1 AUTHOR

Graham Knop <graham@plainblack.com>

=head1 LICENSE

Copyright (c) Graham Knop.

This library is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.

=cut

