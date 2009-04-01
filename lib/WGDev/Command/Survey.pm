package WGDev::Command::Survey;
use strict;
use warnings;
use 5.008008;

our $VERSION = '0.1.0';

use WGDev::Command::Base;
BEGIN { our @ISA = qw(WGDev::Command::Base) }

sub option_config {
    return qw(
        check
        branching
        dump
        revisions
        stats
        graph
    );
}

my $LENGTH_LIMIT = 5000;

sub process {
    my $self    = shift;
    my $wgd     = $self->wgd;
    my $session = $wgd->session();

    my @parents     = $self->arguments;
    my $show_header = @parents > 1;
    while ( my $parent = shift @parents ) {
        my $asset;
        if ( !eval { $asset = $wgd->asset->find($parent) } ) {
            warn "wgd survey: $parent: No such asset\n";
            next;
        }
        if ( !$asset->isa('WebGUI::Asset::Wobject::Survey') ) {
            warn "wgd survey: not a survey instance: $parent";
            next;
        }
        if ($show_header) {
            print "$parent:\n";
        }

        #        print "\n" . "-" x 80 . "\n";
        #        print "Survey Instance: " . $asset->getTitle . " " . $asset->getUrl . "\n";
        #        print "-" x 80 . "\n";
        #
        #        if ( $self->option('revisions') ) {
        #            foreach my $revision ( @{ $asset->getRevisions() } ) {
        #                next unless $revision;
        #
        #                my $revisionDate = WebGUI::Asset->getCurrentRevisionDate( $session, $revision->getId );
        #                print "\nRevision $revisionDate\n";
        #
        #                $self->check( $session, $revision );
        #            }
        #        }

        if ( $self->option('check') ) {
            $self->check( $session, $asset );
        }

        if ( $self->option('branching') ) {
            $self->branching( $session, $asset );
        }

        if ( $self->option('dump') ) {
            $self->dump( $session, $asset );
        }

        if ( $self->option('stats') ) {
            $self->stats( $session, $asset );
        }

        if ( $self->option('graph') ) {
            $self->graph( $session, $asset );
        }
    }
    return 1;
}

sub check {
    my ( $self, $session, $survey ) = @_;

    my $dirty;
    foreach my $s ( @{ $survey->surveyJSON->sections } ) {
        print "\nSection:\t" . $s->{title} . "\t length " . length $s->{text} . "\n";
        if ( length $s->{text} > $LENGTH_LIMIT ) {
            print "--> Marking S for repair..\n";
            $dirty = 1;
            $s->{text} = 'truncated';
        }
        foreach my $q ( @{ $s->{questions} } ) {
            print "Question:\t" . $q->{variable} . "\t length: " . length $q->{text} . "\n";
            if ( length $q->{text} > $LENGTH_LIMIT ) {
                print "\n--> Marking q for repair..\n";
                $dirty = 1;
                $q->{text} = 'truncated';
            }
            elsif ( $q->{text} eq 'truncated' ) {
                print "--> has been truncated\n";
            }

            foreach my $a ( @{ $q->{answers} } ) {
                print "Answer:\t-\t length: " . length $a->{text} . "\n";
                if ( length $a->{text} > $LENGTH_LIMIT ) {
                    print "\n--> Marking a for repair..\n";
                    $dirty = 1;
                    $a->{text} = 'truncated';
                }
                elsif ( $a->{text} eq 'truncated' ) {
                    print "--> has been truncated\n";
                }
            }
        }
    }

    #    $survey->persistSurveyJSON() if $dirty;

    #            print(Dumper(
    #                    {   survey   => $survey->survey->{survey},
    #                        sections => $survey->survey->{sections},
    #                    }
    #                )
    #            );
}

sub dump {
    my ( $self, $session, $survey ) = @_;

    print <<END_TEXT;
# Each line of this document is used to generate a unit test of the ePASS
# branching logic.
#
# The format for each line is:
# <Question> <Answer> <Expect>
#
# For example, the following line:
#  PD3a  "Yes"  PD3b 
# says that if the "Yes" answer is given for question PD1, we expect the next
# question to be PD2a.
#
# Currently we only test 'goto' branching. gotoExpressions are coming soon.
#
# Anything after '#' on a line is treated as a comment.
END_TEXT

    my @printlist;
    foreach my $s ( @{ $survey->surveyJSON->sections } ) {

        my $print_section = 1;

        foreach my $q ( @{ $s->{questions} } ) {

            # Print print queue
            print sprintf( '%-20s%-30s%-20s', $_->[0], "\"$_->[1]\"", $q->{variable} ) . "\n" for @printlist;
            print "\n";
            @printlist = ();

            if ($print_section) {
                print "###########\n";
                print "# Section [$s->{variable}] \"$s->{title}\"\n";
                print "###########\n";
                $print_section = 0;
            }

            foreach my $a ( @{ $q->{answers} } ) {
                push @printlist, [ $q->{variable}, $a->{text} ];
            }
        }
    }
}

sub stats {
    my ( $self, $session, $survey ) = @_;

    my %qtypes;
    my %count = (
        's_goto'           => 0,
        's_gotoExpression' => 0,
        q_goto             => 0,
        q_gotoExpression   => 0,
        a_goto             => 0,
        a_gotoExpression   => 0,
    );
    my %vars;
    my @undefined_vars;
    my @non_required_qs;

    my $sNum = 0;
    foreach my $s ( @{ $survey->surveyJSON->sections } ) {
        $sNum++;

        $count{s}++;
        $count{'s_goto'}++           if $s->{goto};
        $count{'s_gotoExpression'}++ if $s->{gotoExpression};
        if ( $s->{variable} ) {
            $vars{ $s->{variable} }++;
        }
        else {
            push @undefined_vars, "S$sNum";
        }

        my $qNum = 0;
        foreach my $q ( @{ $s->{questions} } ) {
            $qNum++;

            $count{q}++;
            $qtypes{ $q->{questionType} }++;
            $count{q_goto}++           if $q->{goto};
            $count{q_gotoExpression}++ if $q->{gotoExpression};
            if ( $q->{variable} ) {
                $vars{ $q->{variable} }++;
            }
            else {
                push @undefined_vars, "S$sNum-Q$qNum";
            }
            push @non_required_qs, $q->{variable} || "S$sNum-Q$qNum" unless $q->{required};

            my $aNum = 0;
            foreach my $a ( @{ $q->{answers} } ) {
                $aNum++;

                $count{a}++;
                $count{a_goto}++           if $a->{goto};
                $count{a_gotoExpression}++ if $a->{gotoExpression};
            }
        }
    }

    my @qtypes;
    while ( my ( $qtype, $n ) = each %qtypes ) {
        push @qtypes, "$qtype ($n)";
    }
    my $qtypes = ( join "\n ", @qtypes ) || 'None';

    my @duplicate_vars;
    while ( my ( $var, $n ) = each %vars ) {
        push @duplicate_vars, $var if $n > 1;
    }
    my $duplicate_vars = ( join "\n ", @duplicate_vars ) || 'None';

    my $undefined_sections  = ( join "\n ", grep { $_ =~ m/^S\d+$/ } @undefined_vars )      || 'None';
    my $undefined_questions = ( join "\n ", grep { $_ =~ m/^S\d+-Q\d+$/ } @undefined_vars ) || 'None';
    my $non_required_questions = ( join "\n ", @non_required_qs ) || 'None';

    print <<"END_REPORT";
Totals:
 Sections:  $count{s} ($count{s_goto} with goto, $count{s_gotoExpression} with gotoExpression)
 Questions: $count{q} ($count{q_goto} with goto, $count{q_gotoExpression} with gotoExpression)
 Answers:   $count{a} ($count{a_goto} with goto, $count{a_gotoExpression} with gotoExpression)

Question Types: 
 $qtypes

Duplicate Variables:
 $duplicate_vars
 
Undefined Sections:
 $undefined_sections

Undefined Questions:
 $undefined_questions

Non-required Questions:
 $non_required_questions
END_REPORT
}

sub branching {
    my ( $self, $session, $survey ) = @_;

    my $sNum = 0;
    foreach my $s ( @{ $survey->surveyJSON->sections } ) {
        $sNum++;
        for (qw(goto gotoExpression)) {
            if ( $s->{$_} ) {
                print "S$sNum\t" . "$s->{variable}\t" . "$_\t" . $s->{$_} . "\n";
            }
        }
        my $qNum = 0;
        foreach my $q ( @{ $s->{questions} } ) {
            $qNum++;
            for (qw(goto gotoExpression)) {
                if ( $q->{$_} ) {
                    print "S$sNum-Q$qNum\t" . "$s->{variable}-$q->{variable}\t" . "$_\t" . $q->{$_} . "\n";
                }
            }
            my $aNum = 0;
            foreach my $a ( @{ $q->{answers} } ) {
                $aNum++;
                for (qw(goto gotoExpression)) {
                    if ( $a->{$_} ) {
                        print "S$sNum-Q$qNum-A$aNum\t"
                            . "$s->{variable}-$q->{variable}-$a->{text}\t" . "$_\t"
                            . $a->{$_} . "\n";
                    }
                }
            }
        }
    }
}

#-------------------------------------------------------------------

=head2 generateGraph ( )

Generates the Flux Graph using GraphViz. This is currently just a proof-of-concept.
The image is stored at /uploads/FluxGraph.png and overwritten every time this method is called.

Currently only simple GraphViz features are used to generate the graph. Later we will
probably take advantage of html-like processing capabilities to improve the output.

GraphViz must be installed for this to work.

=cut

sub graph {
    my ( $self, $session, $survey ) = @_;

    use GraphViz;
    use Readonly;

    Readonly my $PATH => 'survey.png';
    Readonly my $FONTSIZE => 10;
    
    # Create the GraphViz object used to generate the image
    my $g = GraphViz->new( bgcolor => 'white', fontsize => $FONTSIZE, layout => 'neato');
    
    $g->add_node(
        'Start',
        label     => 'Start',
        fontsize  => $FONTSIZE,
        shape     => 'ellipse',
        style     => 'filled',
        color     => 'CornflowerBlue',
        fillcolor => 'Green',
    );
    
    my $very_first = 1;
    
    my @fall_through;
    my $sNum = 0;
    foreach my $s ( @{ $survey->surveyJSON->sections } ) {
        $sNum++;

        my $s_id = $s->{variable} || "S$sNum";
        $g->add_node(
            $s_id,
            label     => $s_id,
            fontsize  => $FONTSIZE,
            shape     => 'ellipse',
            style     => 'filled',
            color     => 'CornflowerBlue',
            fillcolor => 'LightYellow',
        );
        
        # See if this is the very first node
        if ($very_first) {
            $g->add_edge( 
                'Start' => $s_id,
                taillabel      => 'Begin e-PASS',
                labelfontcolor => 'CornflowerBlue',
                labelfontsize  => $FONTSIZE,
                color          => 'CornflowerBlue'
            );
            $very_first = 0;
        }
        
        # See if there are any fall_throughs waiting 
        # if so, "next" == this section
        while (my $f = pop @fall_through) {
            $g->add_edge( 
                $f->{from} => $s_id,
                taillabel      => $f->{taillabel},
                labelfontcolor => 'CornflowerBlue',
                labelfontsize  => $FONTSIZE,
                color          => 'CornflowerBlue'
            );
        }

        my $qNum = 0;
        foreach my $q ( @{ $s->{questions} } ) {
            $qNum++;

            my $q_id = $q->{variable} || "S$sNum-Q$qNum";

            # Link Section to first Question
            if ( $qNum == 1 ) {
                $g->add_edge( $s_id => $q_id, style => 'dotted' );
            }

            # Add Question node
            $g->add_node(
                $q_id,
                label     => $q_id,
                fontsize  => $FONTSIZE,
                shape     => 'ellipse',
                style     => 'filled',
                color     => 'CornflowerBlue',
                fillcolor => 'LightBlue',
            );
            
            # See if there are any fall_throughs waiting 
            # if so, "next" == this question
            while (my $f = pop @fall_through) {
                $g->add_edge( 
                    $f->{from} => $q_id,
                    taillabel      => $f->{taillabel},
                    labelfontcolor => 'CornflowerBlue',
                    labelfontsize  => $FONTSIZE,
                    color          => 'CornflowerBlue'
                );
            }

            my $aNum = 0;
            foreach my $a ( @{ $q->{answers} } ) {
                $aNum++;

                my $a_id = $a->{text} || "S$sNum-Q$qNum-A$aNum";

                if ( my $goto = $a->{goto} ) {

                    # Link this question to goto target with Answer as taillabel
                    # N.B. goto target could be Section or Question
                    $g->add_edge(
                        $q_id          => $goto,
                        taillabel      => $a_id,
                        labelfontcolor => 'CornflowerBlue',
                        labelfontsize  => $FONTSIZE,
                        color          => 'CornflowerBlue'
                    );
                }
                else {

                    # Link this question to next question with Answer as taillabel
                    push @fall_through,
                        {
                        from      => $q_id,
                        taillabel => $a_id,
                        };
                }
            }
        }
    }

    # Render the image to a file
    $g->as_png($PATH);

    return $PATH;
}

1;

__END__

=head1 NAME

WGDev::Command::Survey - Manipulate Survey instances

=head1 SYNOPSIS

    wgd survey 

=head1 DESCRIPTION


=head1 OPTIONS

=over 8

=item C<--number> C<-n>

Number of GUIDs to generate. Defaults to 1.

=item C<--dashes>

Whether or not to filter GUIDs containing dashes (for easy double-click copy/pasting)

=back

=head1 AUTHOR

Patrick Donelan <pat@patspam.com>

=head1 LICENSE

Copyright (c) Patrick Donelan.  All rights reserved.

This library is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.

=cut

