#!/usr/bin/perl
use Nagios::Plugin;
use LWP;
use HTML::TreeBuilder;
use strict;

my $PROGNAME = 'check_id-pilet';
our $VERSION = '0.2010';

our $p = Nagios::Plugin->new(
	usage => "Usage: %s [ -v|--verbose ] [-t <timeout>]
    [ -i|--id=<id> ]
	",

	version => $VERSION,
    blurb => 'This plugin checks for the validity of pilet.ee tickets.',

	plugin  => $PROGNAME,
	shortname => $PROGNAME,
	timeout => 15,
);

$p->add_arg(
    spec => 'id|i=s',
    help => q(Personal Identifier Number to check (ID-Card numbers no longer supported)),
	required => 1,
);
$p->add_arg(
	spec => 'critical|c=s',
	help => q(Critical treshold for ticket expire. [smhd] multiplier maybe used.),
	required => 0,
	default => 24,
);
$p->add_arg(
	spec => 'warning|w=s',
	help => q(Warning treshold for ticket expire. [smhd] multiplier maybe used.),
	required => 0,
	default => 48,
);

$p->getopts;

my $verbose = $p->opts->verbose;
my $id = uc $p->opts->id;
my $ua = LWP::UserAgent->new();
$ua->agent($PROGNAME.'/'. $VERSION);
my $url = 'https://www.pilet.ee/cgi-bin/splususer/splususer.cgi?op=checkbyid';

my $res = $ua->post($url, { idcode => $id });
unless ($res->is_success) {
	$p->nagios_exit(CRITICAL, $res->status_line);
}

my $root = new HTML::TreeBuilder;
$root->parse($res->content);

my $div = $root->look_down(_tag => 'div', class => 'col col04 content') or $p->nagios_exit(CRITICAL, "Couldn't parse HTML");

# we got list of tickets
if ($div->look_down(_tag => 'li', class => 'future')) {
	print "parse tickets list\n" if $verbose;
	my %map = (
		'Pileti tüüp' => 'type',
		'Kehtivuse lõppaeg' => 'end',
		'Ostmise aeg' => 'purchase',
		'Kehtivuse algusaeg' => 'start',
	);

	use Time::Local qw(timelocal);
	sub parse_date {
		# 07.11.2006 23:59:59
		# 27.03.2009 16:20:59 (aegunud)
		my ($str) = ($_[0] =~ m/^(.*?)\s*(?:\(aegunud\))?$/);
		my ($date, $time) = split(/ /, $str, 2);
		my @date = (reverse(split /:/, $time), split(/\./, $date));
		$date[4]--;
		$date[5] -= 1900;
		my $ts = timelocal(@date);
	}

	# gather detailed ticket information
	my @tickets;
	my $table = $div->look_down('_tag' => 'table',  class => 'data');
	for my $t ($table->find('tr')) {
		#
		# <tr class="past">
		# <td class="bold">Tallinna 1 p&Atilde;&curren;eva kaart</td>
		# <td class="right">40.00</td>
		# <td class="sorted">26.03.2009 16:21:00 -<br />27.03.2009 16:20:59 (aegunud)</td>
		# <td> - </td>
		# </tr>
		#
		my @td = $t->find('td') or next;

		my %td = (
			type => $td[0]->as_text,
			price => $td[1]->as_text,
			period => $td[2]->as_text,
		);

		# '26.03.2009 16:21:00 -27.03.2009 16:20:59 (aegunud)',
		my @period = split(/-/, $td{period}, 2);

		my %ticket = (type => $td{type}, start => parse_date($period[0]), end => parse_date($period[1]));
		print "add ticket: type: $ticket{type}; start: $ticket{start}; end: $ticket{end}\n" if $verbose;
		push(@tickets, { %ticket });
	}

	$p->nagios_exit(WARNING, "No tickets found") unless @tickets;

	sub parse_time {
		my $str = $_[0];
		my ($v, $m) = ($str =~ /^(\d+)([smhd])?$/);
		$v *= 60*60 unless defined $m;
		$v *= 60 if $m eq 'm';
		$v *= 60*60 if $m eq 'h';
		$v *= 60*60*24 if $m eq 'd';
		$v;
	}

	my $warn = parse_time($p->opts->warning);
	my $crit = parse_time($p->opts->critical);
	print "warn: $warn; crit: $crit\n" if $verbose;

	if ($crit >= $warn) {
		$p->nagios_exit(CRITICAL, "critical level has to be smaller than warning level");
	}

	# find first active ticket
	my $now = time();
	for my $t (@tickets) {
		print "check: $t->{start}; $t->{end}\n" if $verbose;
		if ($t->{start} > $now) {
			# ticket in the future, check if it's start period fits to critical range
			if ($t->{start} - $now < $crit) {
				print "found ticket from future\n" if $verbose;
				my $tm = localtime($t->{end});
				$p->nagios_exit(OK, "Ticket '$t->{type}' expires on $tm");
			}
		}
		if ($t->{start} < $now && $t->{end} >= $now) {
			print "found active ticket\n" if $verbose;
			my $tm = localtime($t->{end});
			# found active ticket, but is it critical/warning level?
			if ($t->{end} - $now < $crit) {
				$p->nagios_exit(CRITICAL, "Ticket '$t->{type}' expires on $tm");
			}
			if ($t->{end} - $now < $warn) {
				$p->nagios_exit(WARNING, "Ticket '$t->{type}' expires on $tm");
			}
			$p->nagios_exit(OK, "Ticket '$t->{type}' expires on $tm");
		}
	}
	$p->nagios_exit(CRITICAL, "No active tickets found");
}

my $t = $div->look_down(_tag => 'p', class => 'msg-ok') or $p->nagios_exit(CRITICAL, "Couldn't parse html");
$t = $t->as_text;
print "recv:$t\n" if $verbose;

$p->nagios_exit(OK, "Ticket $id valid") if $t =~ /^Isikul isikukoodiga \Q$id\E on hetkel kehtiv transpordivahendi ID-pilet\.$/;
$p->nagios_exit(CRITICAL, "Ticket $id not valid") if $t =~ /^Isikul isikukoodiga \Q$id\E ei ole olemas hetkel kehtivat ID-piletit\.$/; # TODO
$p->nagios_exit(WARNING, "No active tickets") if $t =~ /^ID-kaardi nr \Q$id\E omanikuga ei ole seotud ühtegi kehtivat ID-piletit\.$/; # TODO
$p->nagios_exit(UNKNOWN, "Need specific ticket ID") if $t =~ /^ID-kaardi nr \Q$id\E omanikuga on seotud järgmised ID-piletid\.$/; # TODO
$p->nagios_exit(CRITICAL, "Invalid input") if $t =~ /^Vigane ID-kaardi number või isikukood\.$/; # TODO
$p->nagios_exit(UNKNOWN, "Unknown parse status: ".$t);
