package Makefile::AST::Evaluator;

use strict;
use warnings;

#use Smart::Comments;
use File::stat;

# XXX put these globals to some better place
our ($Quiet, $JustPrint, $IgnoreErrors);

sub new ($$) {
    my $class = ref $_[0] ? ref shift : shift;
    my $ast = shift;
    return bless {
        ast     => $ast,
        updated => {},
        mtime_cache => {},
        parent_target => undef,
        targets_making => {},
        required_targets => {},
    }, $class;
}

sub ast ($) { $_[0]->{ast} }

sub mark_as_updated ($$) {
    my ($self, $target) = @_;
    ### marking target as updated: $target
    $self->{updated}->{$target} = 1;
}

sub is_updated ($$) {
    my ($self, $target) = @_;
    $self->{updated}->{$target};
}

# update the mtime cache with -M $file
sub update_mtime ($$@) {
    my ($self, $file, $cache) = @_;
    $cache ||= $self->{mtime_cache};
    if (-e $file) {
        my $stat = stat $file or
            die "$0: *** stat failed on $file: $!\n";
        ### set mtime for file: $file
        ### mtime: $stat->mtime
        return ($cache->{$file} = $stat->mtime);
    } else {
        ### file not found: $file
        return ($cache->{$file} = undef);
    }
}

# get -M $file from cache (if any) or set the cache
#  key-value pair otherwise
sub get_mtime ($$) {
    my ($self, $file) = @_;
    my $cache = $self->{mtime_cache};
    if (!exists $cache->{$file}) {
        # set the cache
        return $self->update_mtime($file, $cache);
    }
    return $cache->{$file};
}

sub set_required_target ($$) {
    my ($self, $target) = @_;
    $self->{required_targets}->{$target} = 1;
}

sub is_required_target ($$) {
    my ($self, $target) = @_;
    $self->{required_targets}->{$target};
}

sub make ($$) {
    my ($self, $target) = @_;
    my $making = $self->{targets_making};
    if ($making->{$target}) {
        warn "$0: Circular $target <- $target ".
            "dependency dropped.\n";
        return 'UP_TO_DATE';
    } else {
        $making->{$target} = 1;
    }
    my $retval;
    my @rules = $self->ast->apply_explicit_rules($target);
    ### number of explicit rules: scalar(@rules)
    if (@rules == 0) {
        delete $making->{$target};
        return $self->make_by_rule($target => undef);
    }
    for my $rule (@rules) {
        my $ret;
        ### explicit rule for: $target
        ### explicit rule: $rule->as_str
        if (!$rule->has_command) {
            ## THERE!!!
            $ret = $self->make_implicitly($target);
            ### make_implicitly returned: $ret
            $retval = $ret if !$retval || $ret eq 'REBUILT';
        }
        # XXX unconditional?
        $ret = $self->make_by_rule($target => $rule);
        ### make_by_rule returned: $ret
        $retval = $ret if !$retval || $ret eq 'REBUILT';
    }
    delete $making->{$target};

    # postpone the timestamp propagation until all individual
    # rules have been updated:
    $self->update_mtime($target);

    # postpone the timestamp propagation until all individual
    # rules have been updated:
    $self->update_mtime($target);
    return $retval;
}

sub make_implicitly ($$) {
    my ($self, $target) = @_;
    my $rule = $self->ast->apply_implicit_rules($target);
    if ($rule) {
    ### implicit rule: $rule->as_str
    }
    my $retval = $self->make_by_rule($target => $rule);
    if ($retval eq 'REBUILT') {
        for my $target ($rule->other_targets) {
            $self->mark_as_updated($target);
        }
    }
    return $retval;
}

sub make_by_rule ($$$) {
    my ($self, $target, $rule) = @_;
    ### make_by_rule: $target
    return 'UP_TO_DATE'
        if $self->is_updated($target) and $rule->colon eq ':';
    # XXX the parent should be passed via arguments or local vars
    my $parent = $self->{parent_target};
    if (!$rule) {
        ## HERE!
        ## exists? : -f $target
        if (-f $target) {
            return 'UP_TO_DATE';
        } else {
            if ($self->is_required_target($target)) {
                my $msg =
                    "$0: *** No rule to make target `$target'";
                if (defined $parent) {
                    $msg .=
                        ", needed by `$parent'";
                }
                die "$msg.  Stop.\n";
            } else {
                return 'UP_TO_DATE';
            }
        }
    }
    ### make by rule: $rule->as_str
    my $target_mtime = $self->get_mtime($target);
    my $out_of_date = !defined $target_mtime;
    my $prereq_rebuilt;
    $self->{parent_target} = $target;
    for my $prereq (@{ $rule->normal_prereqs }) {
        # XXX handle order-only prepreqs here
        ### processing rereq: $prereq
        $self->set_required_target($prereq);
        my $res = $self->make($prereq);
        ### make returned: $res
        if ($res and $res eq 'REBUILT') {
            $out_of_date++;
            $prereq_rebuilt++;
        } elsif ($res and $res eq 'UP_TO_DATE') {
            if (!$out_of_date) {
                if ($self->get_mtime($prereq) > $target_mtime) {
                    ### prereq file is newer: $prereq
                    $out_of_date = 1;
                }
            }
        } else {
            die "Unexpected returned value: $res";
        }
    }
    $self->{parent_target} = undef;
    if ($out_of_date) {
        ### firing rule's commands: $rule->as_str
        $rule->run_commands($self->ast);
        $self->mark_as_updated($rule->target)
            if $rule->colon eq ':';
        return 'REBUILT'
            if $rule->has_command or $prereq_rebuilt;
    }
    return 'UP_TO_DATE';
}

1;
__END__

