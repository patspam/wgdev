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
        setVariables
        setAllRequired
    );
}

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
            $self->check( $session, $asset, $self->option('fix') );
        }
        
        if ( $self->option('fix') ) {
            $self->check( $session, $asset, 1 );
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
        
        if ( $self->option('setVariables') ) {
            $self->set_variables( $session, $asset );
        }
        
        if ( $self->option('setAllRequired') ) {
            $self->set_all_required( $session, $asset );
        }
        
    }
    return 1;
}

=head2

Set Section and Question variables from title text

=cut

sub set_variables {
    my ( $self, $session, $survey ) = @_;

    my $sNum = 0;
    foreach my $s ( @{ $survey->surveyJSON->sections } ) {
        $sNum++;
        if (!$s->{variable}) {
            my $new_var = $s->{title} !~ m/^S_/ ? "S_$s->{title}" : $s->{title};
            print  "$sNum -> $new_var\n";
            $s->{variable} = $new_var;
        }
        my $qNum;
        foreach my $q ( @{ $s->{questions} } ) {
            $qNum++;
            if (!$q->{variable}) {
                my $new_var = $q->{title};
                print  "$sNum-$qNum -> $new_var\n";
                $q->{variable} = $new_var;
            }
        }
    }
    $survey->persistSurveyJSON;
}

=head2

Sets the required flag to 1 on all questions 

=cut

sub set_all_required {
    my ( $self, $session, $survey ) = @_;

    my $sNum = 0;
    foreach my $s ( @{ $survey->surveyJSON->sections } ) {
        $sNum++;
        my $qNum;
        foreach my $q ( @{ $s->{questions} } ) {
            $qNum++;
            if (!$q->{required}) {
                print  "Setting required flag on $sNum-$qNum\n";
                $q->{required} = 1;
            }
        }
    }
    $survey->persistSurveyJSON;
}

=head2 check

Check for corruption

=cut

sub check {
    my ( $self, $session, $survey, $fix ) = @_;
    
    my $LENGTH_LIMIT = 5000;

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

    if ($fix) {
        $survey->persistSurveyJSON() if $dirty;
    }
}

=head2 dump

Dump survey structure

=cut

sub dump {
    my ( $self, $session, $survey ) = @_;

    print <<END_TEXT;
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

=head2 stats

Show survey stats

=cut

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

=head2 branching

Dumps brief outline of survey branching

=cut

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

=head2 graph ( )

Generates a graph visualisation to survey.svg using GraphViz.

=cut

sub graph {
    my ( $self, $session, $survey ) = @_;

    use GraphViz;
    use Readonly;

    Readonly my $OUTPUT_FILE => 'survey';
    Readonly my $OUTPUT_TYPE => 'svg';
    Readonly my $FONTSIZE => 10;

    Readonly my %COLOR => (
        bg                   => 'white',
        start                => 'CornflowerBlue',
        start_fill           => 'Green',
        section              => 'CornflowerBlue',
        section_fill         => 'LightYellow',
        question             => 'CornflowerBlue',
        question_fill        => 'LightBlue',
        start_edge           => 'Green',
        fall_through_edge    => 'CornflowerBlue',
        goto_edge            => 'DarkOrange',
        goto_expression_edge => 'DarkViolet',
    );

    # Create the GraphViz object used to generate the image
    # N.B. dot gives vertical layout, neato gives purdy circular
    my $g = GraphViz->new( bgcolor => $COLOR{bg}, fontsize => $FONTSIZE, layout => 'dot', overlap => 'orthoyx');

    $g->add_node(
        'Start',
        label     => 'Start',
        fontsize  => $FONTSIZE,
        shape     => 'ellipse',
        style     => 'filled',
        color     => $COLOR{start},
        fillcolor => $COLOR{start_fill},
    );

    my $very_first = 1;

    my $add_goto_edge = sub {
        my ( $obj, $id, $taillabel ) = @_;
        return unless $obj;

        if ( my $goto = $obj->{goto} ) {
            $g->add_edge(
                $id => $goto,
                taillabel => $taillabel || 'Jump To',
                labelfontcolor => $COLOR{goto_edge},
                labelfontsize  => $FONTSIZE,
                color          => $COLOR{goto_edge},
            );
        }
    };

    require WebGUI::Asset::Wobject::Survey::ResponseJSON;
    my $add_goto_expression_edges = sub {
        my ( $obj, $id, $taillabel ) = @_;
        return unless $obj;
        return unless $obj->{gotoExpression};

        my $rj = 'WebGUI::Asset::Wobject::Survey::ResponseJSON';

        for my $gotoExpression ( split /\n/, $obj->{gotoExpression} ) {
            if ( my $processed = $rj->parseGotoExpression( $session, $gotoExpression ) ) {
                $g->add_edge(
                    $id            => $processed->{target},
                    taillabel      => $taillabel ? "$taillabel: $processed->{expression}" :  $processed->{expression},
                    labelfontcolor => $COLOR{goto_expression_edge},
                    labelfontsize  => $FONTSIZE,
                    color          => $COLOR{goto_expression_edge},
                );
            }
        }
    };

    my @fall_through;
    my $sNum = 0;
    foreach my $s ( @{ $survey->surveyJSON->sections } ) {
        $sNum++;

        my $s_id = $s->{variable} || "S$sNum";
        $g->add_node(
            $s_id,
            label     => "$s_id\n($s->{questionsPerPage} questions per page)",
            fontsize  => $FONTSIZE,
            shape     => 'ellipse',
            style     => 'filled',
            color     => $COLOR{section},
            fillcolor => $COLOR{section_fill},
        );

        # See if this is the very first node
        if ($very_first) {
            $g->add_edge(
                'Start'        => $s_id,
                taillabel      => 'Begin e-PASS',
                labelfontcolor => $COLOR{start_edge},
                labelfontsize  => $FONTSIZE,
                color          => $COLOR{start_edge},
            );
            $very_first = 0;
        }

        # See if there are any fall_throughs waiting
        # if so, "next" == this section
        while ( my $f = pop @fall_through ) {
            $g->add_edge(
                $f->{from}     => $s_id,
                taillabel      => $f->{taillabel},
                labelfontcolor => $COLOR{fall_through_edge},
                labelfontsize  => $FONTSIZE,
                color          => $COLOR{fall_through_edge},
            );
        }

        # Add section-level goto and gotoExpression edges
        $add_goto_edge->( $s, $s_id );
        $add_goto_expression_edges->( $s, $s_id );

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
                label     => $q->{required} ? "$q_id *" : $q_id,
                fontsize  => $FONTSIZE,
                shape     => 'ellipse',
                style     => 'filled',
                color     => $COLOR{question},
                fillcolor => $COLOR{question_fill},
            );

            # See if there are any fall_throughs waiting
            # if so, "next" == this question
            while ( my $f = pop @fall_through ) {
                $g->add_edge(
                    $f->{from}     => $q_id,
                    taillabel      => $f->{taillabel},
                    labelfontcolor => $COLOR{fall_through_edge},
                    labelfontsize  => $FONTSIZE,
                    color          => $COLOR{fall_through_edge},
                );
            }

            # Add question-level goto and gotoExpression edges
            $add_goto_edge->( $q, $q_id );
            $add_goto_expression_edges->( $q, $q_id );

            my $aNum = 0;
            foreach my $a ( @{ $q->{answers} } ) {
                $aNum++;

                my $a_id = $a->{text} || "S$sNum-Q$qNum-A$aNum";

                $add_goto_expression_edges->( $a, $q_id, $a_id );
                if ( $a->{goto} ) {
                    $add_goto_edge->( $a, $q_id, $a_id );
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
    my $method = "as_$OUTPUT_TYPE";
    $g->$method("$OUTPUT_FILE.$OUTPUT_TYPE");
}

1;

__END__

=head1 NAME

WGDev::Command::Survey - Manipulate Survey instances

=head1 SYNOPSIS

    wgd survey [--check] [--fix] [--variables] [--dump] [--stats] [--branching] [--graph]

=head1 DESCRIPTION

Various utilities for Survey instances (dump structure, visualise, etc..).

=head1 OPTIONS

=over 8

=item C<--check> C<--fix>

Check for corruption, and optionally try to fix it. 

=item C<--variables>

Set Section and Question variables from title text

=item C<--dump>

Dump Survey structure

=item C<--stats>

Show Survey stats

=item C<--branching>

Dumps brief outline of survey branching

=item C<--graph>

Generates a graph visualisation to survey.svg using GraphViz.

=back

=head1 AUTHOR

Patrick Donelan <pat@patspam.com>

=head1 LICENSE

Copyright (c) Patrick Donelan.  All rights reserved.

This library is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.

=cut

