package WGDev::Command::Reset;
use strict;
use warnings;
use 5.008008;

our $VERSION = '0.3.0';

use WGDev::Command::Base::Verbosity;
BEGIN { our @ISA = qw(WGDev::Command::Base::Verbosity) }

use File::Spec ();
use Carp qw(croak);
use constant STAT_MODE => 2;
use constant STAT_UID  => 4;
use constant STAT_GID  => 5;

sub config_options {
    return (
        shift->SUPER::config_options, qw(
            fast|f

            backup!
            delcache!
            import!

            test|t
            dev|d
            build|b

            uploads!
            upgrade!

            debug!
            starter!
            clear!
            config!
            purge!
            cleantags!
            emptytrash!
            index!
            runwf!
            util=s@

            delusers

            profile|pro|p=s@
            ) );
}

sub parse_params {
    my ( $self, @args ) = @_;
    $self->option( 'delcache' => 1 );
    return $self->SUPER::parse_params(@args);
}

sub option_profile {
    my $self           = shift;
    my $profile        = shift;
    my $profile_string = $self->wgd->my_config( [ 'profiles', $profile ] );
    if ( !defined $profile_string ) {
        warn "Profile '$profile' does not exist!\n";
        return;
    }
    $self->parse_params_string($profile_string);
    return;
}

sub option_fast {
    my $self = shift;
    $self->option( uploads   => 0 );
    $self->option( backup    => 0 );
    $self->option( delcache  => 0 );
    $self->option( purge     => 0 );
    $self->option( cleantags => 0 );
    $self->option( index     => 0 );
    $self->option( runwf     => 0 );
    return;
}

sub option_dev {
    my $self = shift;
    $self->option( backup  => 1 );
    $self->option( import  => 1 );
    $self->option( uploads => 1 );
    $self->option( upgrade => 1 );
    $self->option( starter => 0 );
    $self->option( debug   => 1 );
    $self->option( clear   => 1 );
    return;
}

sub option_build {
    my $self = shift;
    $self->verbosity( $self->verbosity + 1 );
    $self->option( backup     => 1 );
    $self->option( uploads    => 1 );
    $self->option( import     => 1 );
    $self->option( starter    => 1 );
    $self->option( debug      => 0 );
    $self->option( upgrade    => 1 );
    $self->option( purge      => 1 );
    $self->option( emptytrash => 1 );
    $self->option( cleantags  => 1 );
    $self->option( index      => 1 );
    $self->option( runwf      => 1 );
    return;
}

sub process {
    my $self = shift;
    my $wgd  = $self->wgd;

    if ( $self->option('backup') ) {
        $self->backup;
    }

    # Clear cache
    if ( $self->option('delcache') ) {
        $self->clear_cache;
    }

    # Delete non-system users
    if ( $self->option('delusers') ) {
        $self->delete_users;
    }

    # Clear and recreate uploads
    if ( $self->option('uploads') ) {
        $self->reset_uploads;
    }

    if ( $self->option('import') ) {
        $self->import_db_script;
    }

    # Run the upgrade in a fork
    if ( $self->option('upgrade') ) {
        $self->upgrade;
    }

    if ( $self->option('config') ) {
        $self->reset_config;
    }

    if ( defined $self->option('debug') || defined $self->option('starter') )
    {
        $self->set_settings;
    }

    if ( $self->option('clear') ) {
        $self->clear_default_content;
    }

    if ( $self->option('purge') ) {
        $self->purge_old_revisions;
    }

    if ( $self->option('emptytrash') ) {
        $self->empty_trash;
    }

    if ( $self->option('cleantags') ) {
        $self->clean_version_tags;
    }

    if ( $self->option('runwf') ) {
        $self->run_all_workflows;
    }

    if ( $self->option('index') ) {
        $self->rebuild_lineage;
        $self->rebuild_index;
    }

    if ( $self->option('util') ) {
        require WGDev::Command::Util;
        for my $util ( @{ $self->option('util') } ) {
            $self->report("Running utility script '$util'... ");
            $self->report( 2, "\n" );
            my $util_command = WGDev::Command::Util->new($wgd);
            $util_command->parse_params_string($util);
            $util_command->verbosity( $self->verbosity - 1 );
            if ( !$util_command->process ) {
                die "Error running util script!\n";
            }
            $self->report("Done.\n");
        }
    }

    return 1;
}

sub backup {
    my $self = shift;
    $self->report('Backing up current database... ');
    $self->wgd->db->dump(
        File::Spec->catfile( File::Spec->tmpdir, 'WebGUI-reset-backup.sql' )
    );
    $self->report("Done.\n");
    return 1;
}

sub clear_cache {
    my $self = shift;
    my $wgd  = $self->wgd;
    require File::Path;
    $self->report('Clearing cache... ');
    if ( $wgd->config->get('cacheType') eq 'WebGUI::Cache::FileCache' ) {
        my $cache_dir = $wgd->config->get('fileCacheRoot')
            || '/tmp/WebGUICache';
        File::Path::rmtree($cache_dir);
    }
    elsif ( $wgd->config->get('cacheType') eq 'WebGUI::Cache::Database' ) {

   # Don't clear the DB cache if we are importing, as that will wipe it anyway
        if ( !$self->option('import') ) {
            my $dsn = $wgd->db->connect;
            $dsn->do('DELETE FROM cache');
        }
    }
    else {

        # Can't clear a cache we don't know anything about
    }
    $self->report("Done.\n");
    return 1;
}

sub delete_users {
    my $self = shift;
    my $wgd  = $self->wgd;

    my $session = $wgd->session;
    my @user_ids = grep { $_ ne '1' && $_ ne '3' }
        map { @{$_} }
        @{ $wgd->db->fetchall_arrayref('SELECT userId FROM users') };
    my $n_users = @user_ids;
    $self->report("Deleting $n_users non-system users... ");
    $self->report( 2, "\n" );
    require WebGUI::User;

    for my $user_id (@user_ids) {
        my $user = WebGUI::User->new( $session, $user_id );
        $self->report( 2, "\tDeleting user '" . $user->username . "'.\n" );
        $user->delete;
    }
    $self->report("Done.\n");
    return 1;
}

# Clear and recreate uploads
sub reset_uploads {
    my $self = shift;
    my $wgd  = $self->wgd;
    require File::Copy;
    require File::Find;
    require File::Path;
    $self->report('Recreating uploads... ');

    my $wg_uploads = File::Spec->catdir( $wgd->root, 'www', 'uploads' );
    my $site_uploads = $wgd->config->get('uploadsPath');

    my $initial_umask = umask;
    my ( $uploads_mode, $uploads_uid, $uploads_gid )
        = ( stat $site_uploads )[ STAT_MODE, STAT_UID, STAT_GID ];

    ##no critic (ProhibitPunctuationVars ProhibitParensWithBuiltins)
    # make umask as permissive as required to match existing uploads folder
    # including sticky bits
    umask( oct(7777) & ~$uploads_mode );

    # set effective UID and GID
    local ( $>, $) ) = ( $uploads_uid, $uploads_gid );

    File::Path::rmtree( $site_uploads, { keep_root => 1 } );

    File::Find::find( {
            no_chdir => 1,
            wanted   => sub {
                no warnings 'once';
                my $wg_path = $File::Find::name;
                my $site_path
                    = File::Spec->rel2abs(
                    File::Spec->abs2rel( $wg_path, $wg_uploads ),
                    $site_uploads );
                if ( -d $wg_path ) {
                    my $dir = ( File::Spec->splitdir($wg_path) )[-1];
                    if ( $dir =~ /^[.]/msx ) {
                        $File::Find::prune = 1;
                        return;
                    }
                    File::Path::mkpath( $site_path, 0, $uploads_mode );
                }
                else {
                    File::Copy::copy( $wg_path, $site_path );
                }
            },
        },
        $wg_uploads
    );

    umask $initial_umask;

    $self->report("Done\n");
    return 1;
}

sub import_db_script {
    my $self = shift;
    my $wgd  = $self->wgd;
    $self->report('Clearing old database information... ');
    $wgd->db->clear;
    $self->report("Done.\n");

    $self->report('Importing clean database dump... ');

    # If we aren't upgrading, we're using the current DB version
    my $db_file
        = $self->option('upgrade') ? 'previousVersion.sql' : 'create.sql';
    $wgd->db->load( File::Spec->catfile( $wgd->root, 'docs', $db_file ) );
    $self->report("Done\n");
    return 1;
}

# Run the upgrade in a fork
sub upgrade {
    my $self = shift;
    my $wgd  = $self->wgd;
    $self->report('Running upgrade script... ');

    # TODO: only upgrade single site
    my $pid = fork;
    if ( !$pid ) {

        # replace sub in WebGUI::Config to only return a single config file
        my $config_filename
            = ( File::Spec->splitpath( $wgd->config_file ) )[2];
        my $config_hash = { $config_filename => $wgd->config };
        require WebGUI::Config;
        no warnings qw(once redefine);
        local *WebGUI::Config::readAllConfigs = sub { return $config_hash };

        # child process, don't need to worry about restoring anything
        chdir File::Spec->catdir( $wgd->root, 'sbin' );

        local @ARGV = qw(--doit --override --skipBackup);
        if ( $self->verbosity < 2 ) {
            push @ARGV, '--quiet';
        }
        do 'upgrade.pl';
        croak $@ if $@;
        exit;
    }
    waitpid $pid, 0;

    # error status of subprocess
    if ($?) {    ##no critic (ProhibitPunctuationVars)
        die "Upgrade failed!\n";
    }
    $self->report("Done\n");
    return 1;
}

sub reset_config {
    my $self = shift;
    my $wgd  = $self->wgd;
    require File::Copy;

    $self->report('Resetting config file... ');
    my $reset_config = $wgd->my_config('config');

    # new config file will include any explicit overrides
    my %set_config;
    if ( exists $reset_config->{override} ) {
        %set_config = %{ $reset_config->{override} };
    }

    # will also include specified values copied from old config
    my @copy_keys = qw(
        dsn dbuser dbpass uploadsPath uploadsURL
        exportPath extrasPath extrasURL cacheType
        sitename spectreIp spectrePort spectreSubnets
        fileCacheRoot
        );    # Update POD docs if these change
    if ( exists $reset_config->{copy} ) {
        unshift @copy_keys, @{ $reset_config->{copy} };
    }
    for my $key (@copy_keys) {
        $set_config{$key} = $wgd->config->get($key);
    }

    $wgd->close_config;
    open my $fh, '>', $wgd->config_file
        or croak "Unable to write config file: $!";
    File::Copy::copy(
        File::Spec->catfile( $wgd->root, 'etc', 'WebGUI.conf.original' ),
        $fh );
    close $fh or croak "Unable to write config file: $!";

    my $config = $wgd->config;
    while ( my ( $key, $value ) = each %set_config ) {
        $config->set( $key, $value );
    }

    $self->report("Done\n");
    return 1;
}

sub set_settings {
    my $self = shift;
    my $wgd  = $self->wgd;
    $self->report('Setting WebGUI settings... ');
    my $dbh = $wgd->db->connect;
    my $sth = $dbh->prepare(
        q{REPLACE INTO `settings` (`name`, `value`) VALUES (?,?)});
    if ( $self->option('debug') ) {
        $sth->execute( 'showDebug', 1 );

        # for debug we set this to 1 year
        $sth->execute( 'sessionTimeout', 365 * 24 * 60 * 60 );
    }
    elsif ( defined $self->option('debug') ) {
        $sth->execute( 'showDebug', 0 );

        # default time is 2 hours
        $sth->execute( 'sessionTimeout', 2 * 60 * 60 );
    }
    if ( $self->option('starter') ) {
        $sth->execute( 'specialState', 'init' );
    }
    elsif ( defined $self->option('starter') ) {
        $dbh->do(q{DELETE FROM `settings` WHERE `name`='specialState'});
    }
    $self->report("Done\n");
    return 1;
}

sub clear_default_content {
    my $self = shift;
    my $wgd  = $self->wgd;
    $self->report('Clearing example assets... ');
    $self->report( 2, "\n" );
    my $home     = $wgd->asset->home;
    my $children = $home->getLineage(
        ['descendants'],
        {
            statesToInclude => [
                'published',       'clipboard',
                'clipboard-limbo', 'trash',
                'trash-limbo'
            ],
            statusToInclude => [ 'approved', 'pending', 'archive' ],
            excludeClasses => ['WebGUI::Asset::Wobject::Layout'],
            returnObjects  => 1,
            invertTree     => 1,
        } );
    for my $child ( @{$children} ) {
        $self->report( 2, sprintf "\tRemoving \%-35s '\%s'\n",
            $child->getName, $child->get('title') );
        $child->purge;
    }
    $self->report("Done\n");
    return 1;
}

sub purge_old_revisions {
    my $self = shift;
    my $wgd  = $self->wgd;
    require WebGUI::Asset;
    $self->report('Purging old Asset revisions... ');
    $self->report( 2, "\n" );
    my $sth = $wgd->db->connect->prepare(<<'END_SQL');
    SELECT `assetData`.`assetId`, `asset`.`className`, `assetData`.`revisionDate`
    FROM `asset`
        LEFT JOIN `assetData` ON `asset`.`assetId` = `assetData`.`assetId`
    ORDER BY `assetData`.`revisionDate` ASC
END_SQL
    $sth->execute;
    while ( my ( $id, $class, $revision ) = $sth->fetchrow_array ) {
        my $current_revision
            = WebGUI::Asset->getCurrentRevisionDate( $wgd->session, $id );
        if ( !defined $current_revision || $current_revision == $revision ) {
            next;
        }
        my $asset
            = WebGUI::Asset->new( $wgd->session, $id, $class, $revision )
            || next;
        if ( $asset->getRevisionCount('approved') > 1 ) {
            $self->report( 2, sprintf "\tPurging \%-35s \%s '\%s'\n",
                $asset->getName, $revision, $asset->get('title') );
            $asset->purgeRevision;
        }
    }
    $self->report("Done\n");
    return 1;
}

sub empty_trash {
    my $self = shift;
    my $wgd  = $self->wgd;
    $self->report('Emptying trash... ');
    $self->report( 2, "\n" );
    my $assets = $wgd->asset->root->getLineage(
        ['descendants'],
        {
            statesToInclude => [qw(trash)],
            statusToInclude => [qw(approved archived pending)],
        } );
    for my $asset_id ( @{$assets} ) {
        my $asset = $wgd->asset->by_id($asset_id);
        $self->report( 2, sprintf "\tPurging \%-35s '\%s'\n",
            $asset->getName, $asset->get('title') );
        $asset->purge;
    }
    $self->report("Done\n");
    return 1;
}

sub clean_version_tags {
    my $self = shift;
    my $wgd  = $self->wgd;

    $self->report('Finding current version number... ');
    my $version = $wgd->version->database( $wgd->db->connect );
    $self->report("$version. Done\n");

    $self->report('Cleaning out versions Tags... ');
    my $tag_id = 'pbversion0000000000001';
    my $dbh    = $wgd->db->connect;
    my $sth    = $dbh->prepare(q{UPDATE `assetData` SET `tagId` = ?});
    $sth->execute($tag_id);
    $sth = $dbh->prepare(q{DELETE FROM `assetVersionTag`});
    $sth->execute;
    $sth = $dbh->prepare(<<'END_SQL');
        INSERT INTO `assetVersionTag`
            ( `tagId`, `name`, `isCommitted`, `creationDate`, `createdBy`, `commitDate`,
                `committedBy`, `isLocked`, `lockedBy`, `groupToUse`, `workflowId` )
        VALUES (?,?,?,?,?,?,?,?,?,?,?)
END_SQL
    my $now = time;
    $sth->execute( $tag_id, "Base $version Install",
        1, $now, '3', $now, '3', 0, q{}, '3', q{} );
    $self->report("Done\n");
    return 1;
}

sub run_all_workflows {
    my $self = shift;
    my $wgd  = $self->wgd;
    $self->report('Running all pending workflows... ');
    $self->report( 2, "\n" );
    require WebGUI::Workflow::Instance;
    my $sth = $wgd->db->connect->prepare(
        q{SELECT `instanceId` FROM `WorkflowInstance`});
    $sth->execute;
    while ( my ($instance_id) = $sth->fetchrow_array ) {
        my $instance
            = WebGUI::Workflow::Instance->new( $wgd->session, $instance_id );
        my $waiting_count = 0;
        while ( my $result = $instance->run ) {
            if ( $result eq 'complete' ) {
                $waiting_count = 0;
                next;
            }
            if ( $result eq 'waiting' ) {
                ##no critic (ProhibitMagicNumbers)
                if ( $waiting_count++ > 10 ) {
                    warn
                        "Unable to finish workflow $instance_id, too many iterations!\n";
                    last;
                }
                next;
            }
            if ( $result eq 'done' ) {
            }
            elsif ( $result eq 'error' ) {
                warn "Unable to finish workflow $instance_id.  Error!\n";
            }
            else {
                warn
                    "Unable to finish workflow $instance_id.  Unknown status $result!\n";
            }
            last;
        }
    }
    $self->report("Done\n");
    return 1;
}

sub rebuild_lineage {
    my $self = shift;
    my $wgd  = $self->wgd;
    $self->report('Rebuilding lineage... ');
    my $pid = fork;
    if ( !$pid ) {

        # silence output of rebuildLineage unless we're at max verbosity
        if ( $self->verbosity < 3 ) {    ##no critic (ProhibitMagicNumbers)
            ##no critic (RequireCheckedOpen)
            open STDIN,  '<', File::Spec->devnull;
            open STDOUT, '>', File::Spec->devnull;
            open STDERR, '>', File::Spec->devnull;
        }
        $self->report("\n\n");
        chdir File::Spec->catdir( $wgd->root, 'sbin' );
        local @ARGV = ( '--configFile=' . $wgd->config_file_relative );
        ##no critic (ProhibitPunctuationVars)
        # $0 should have the filename of the script being run
        local $0 = './rebuildLineage.pl';
        do $0;
        exit;
    }
    waitpid $pid, 0;
    $self->report("Done\n");
    return 1;
}

sub rebuild_index {
    my $self = shift;
    my $wgd  = $self->wgd;
    $self->report('Rebuilding search index... ');
    my $pid = fork;
    if ( !$pid ) {

        # silence output of searhc indexer unless we're at max verbosity
        if ( $self->verbosity < 3 ) {    ##no critic (ProhibitMagicNumbers)
            ##no critic (RequireCheckedOpen)
            open STDIN,  '<', File::Spec->devnull;
            open STDOUT, '>', File::Spec->devnull;
            open STDERR, '>', File::Spec->devnull;
        }
        print "\n\n";
        chdir File::Spec->catdir( $wgd->root, 'sbin' );
        local @ARGV
            = ( '--configFile=' . $wgd->config_file_relative, '--indexsite' );
        ##no critic (ProhibitPunctuationVars)
        # $0 should have the filename of the script being run
        local $0 = './search.pl';
        do $0;
        exit;
    }
    waitpid $pid, 0;
    $self->report("Done\n");
    return 1;
}

1;

__END__

=head1 NAME

WGDev::Command::Reset - Reset a site to defaults

=head1 SYNOPSIS

    wgd reset [-v] [-q] [-f] [-d | -b | -t]

=head1 DESCRIPTION

Resets a site to defaults, including multiple cleanup options for setting up
a site for development or for a build.  Can also perform the cleanup functions
without resetting a site.

=head1 OPTIONS

=over 8

=item C<-v> C<--verbose>

Output more information

=item C<-q> C<--quiet>

Output less information

=item C<-f> C<--fast>

Fast mode - equivalent to:
C<--no-upload --no-backup --no-delcache --no-purge --no-cleantags --no-index --no-runwf>

=item C<-t> C<--test>

Test mode - equivalent to:
C<--backup --import>

=item C<-d> C<--dev>

Developer mode - equivalent to:
C<--backup --import --no-starter --debug --clear --upgrade --uploads>

=item C<-b> C<--build>

Build mode - equivalent to:
C<--verbose --backup --import --starter --no-debug --upgrade --purge --cleantags --index --runwf>

=item C<--backup> C<--no-backup>

Backup database before doing any other operations.  Defaults to on.

=item C<--delcache> C<--no-delcache>

Delete the site's cache.  Defaults to on.

=item C<--import> C<--no-import>

Import a database script

=item C<--uploads> C<--no-uploads>

Recreate uploads directory

=item C<--upgrade> C<--no-upgrade>

Perform an upgrade - also controls which database script to import

=item C<--debug> C<--no-debug>

Enable debug mode and increase session timeout

=item C<--starter> C<--no-starter>

Enable the site starter

=item C<--clear> C<--no-clear>

Clear the content off the home page and its children

=item C<--config> C<--no-config>

Resets the site's config file.  Some values like database information will be
preserved.  Additional options can be set in the WGDev config file.

=item C<--emptytrash> C<--no-emptytrash>

Purges all items from the trash

=item C<--purge> C<--no-purge>

Purge all old revisions

=item C<--cleantags> C<--no-cleantags>

Removes all version tags and sets all asset revisions to be
under a new version tag marked with the current version number

=item C<--index> C<--no-index>

Rebuild the site lineage and reindex all of the content

=item C<--runwf> C<--no-runwf>

Attempt to finish any running workflows

=item C<--util=>

Run a utility script.  Script will be run last, being passed to the
L<C<util> command|WGDev::Command::Util>.  Parameter can be specified multiple
times to run additional scripts.

=item C<--profile=> C<--pro=> C<-p>

Specify a profile of options to use for resetting.  Profiles are specified in
the WGDev config file under the C<command.reset.profiles> section.  A profile
is defined as a string to be used as additional command line options.

=back

=head2 WebGUI Config File Reset

The config file is reset by taking the currently specified WebGUI config file,
the F<WebGUI.conf.orig> file that WGDev finds in the F<etc> directory, and
instructions in the WGDev config file (see L<WGDev::Command::Config>).

The reset config file contains in order of priority: options copied from the
existing config file, override options, and options in the F<WebGUI.conf.orig>
file.

Overrides are specified in the config parameter C<command.reset.config.overide>
as a hash of options to apply.  Copied parameters are specified in
C<command.reset.config.copy> as a list of entries to copy.  In addition to the
configured list, a set of parameters is always copied:

    dsn         dbuser          dbpass
    uploadsPath uploadsURL
    extrasPath  extrasURL
    exportPath
    cacheType   fileCacheRoot
    sitename
    spectreIp   spectrePort     spectreSubnets

=head1 CONFIGURATION

=over 8

=item C<< profiles.<profile name> >>

Creates a profile to use with the C<--profile> option.  The value of the config
parameter is a string with the command line parameters to apply when this
profile is used.

=item C<config.overide>

Overrides to apply when resetting config file.

=item C<config.copy>

Parameters to copy from existing config file when resetting it.

=back

=head1 METHODS

=head2 C<option_build>

Enables options for creating a release build.  Equivalent to

    $reset->verbosity( $reset->verbosity + 1 );
    $reset->option( backup     => 1 );
    $reset->option( uploads    => 1 );
    $reset->option( import     => 1 );
    $reset->option( starter    => 1 );
    $reset->option( debug      => 0 );
    $reset->option( upgrade    => 1 );
    $reset->option( emptytrash => 1 );
    $reset->option( purge      => 1 );
    $reset->option( cleantags  => 1 );
    $reset->option( index      => 1 );
    $reset->option( runwf      => 1 );

=head2 C<option_dev>

Enables options for doing development work.  Equivalent to

    $reset->option( backup  => 1 );
    $reset->option( import  => 1 );
    $reset->option( uploads => 1 );
    $reset->option( upgrade => 1 );
    $reset->option( starter => 0 );
    $reset->option( debug   => 1 );
    $reset->option( clear   => 1 );

=head2 C<option_fast>

Enables options for doing a faster reset, usually used along with
other group options or profiles.  Equivalent to

    $reset->option( uploads   => 0 );
    $reset->option( backup    => 0 );
    $reset->option( delcache  => 0 );
    $reset->option( purge     => 0 );
    $reset->option( cleantags => 0 );
    $reset->option( index     => 0 );
    $reset->option( runwf     => 0 );

=head2 C<option_profile>

Reads a profile from the config section C<command.reset.profiles>
and processes it as a string of command line options.

=head2 C<clear_cache>

Clears the site's cache.

=head2 C<backup>

Creates a backup of the site database in the system's temp directory.

=head2 C<reset_uploads>

Clears and recreates the uploads location for a site.

=head2 C<import_db_script>

Imports a base database script for the site.  If
C<< $reset->option('upgrade') >> is set, F<previousVersion.sql> is
used.  Otherwise, F<create.sql> is used.

=head2 C<upgrade>

Performs an upgrade on the site

=head2 C<set_settings>

Enabled/disables debug mode and extended/standard session timeout
based on C<< $reset->option('debug') >> and enables/disables the
site starter based on C<< $reset->option('starter') >>.

=head2 C<reset_config>

Resets the site's config file based on the rules listed in
L</WebGUI Config File Reset>.

=head2 C<empty_trash>

Purges all items from the trash.

=head2 C<purge_old_revisions>

Purges all asset revisions aside from the most recent.

=head2 C<clean_version_tags>

Collapses all version tags into a single tag labeled based on the
current WebGUI version.

=head2 C<clear_default_content>

Removes all content descending from the default asset, excluding
Page Layout assets.

=head2 C<delete_users>

Removes all users from the site, excepting the default users of
Admin and Visitor.

=head2 C<rebuild_index>

Rebuilds the search index of the site using the F<search.pl> script.

=head2 C<rebuild_lineage>

Rebuilds the lineage of the site using the F<rebuildLineage.pl> script.

=head2 C<run_all_workflows>

Attempts to finish processing all active workflows.  Waiting workflows
will be run up to 10 times to complete them.

=head1 AUTHOR

Graham Knop <graham@plainblack.com>

=head1 LICENSE

Copyright (c) Graham Knop.  All rights reserved.

This library is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.

=cut

