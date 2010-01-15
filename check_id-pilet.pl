#!/usr/bin/perl
use Getopt::Long;
use LWP;
use HTML::TreeBuilder;
use Nagios::Plugin;
use strict;

my $PROGNAME = 'check_id-pilet';
our $VERSION = '0.12';

our $p = Nagios::Plugin->new(
	usage => "Usage: %s [ -v|--verbose ] [-t <timeout>]
    [ -i|--id=<id> ]
	",

	version => $VERSION,
    blurb => 'This plugin checks for the validity of id.ee tickets.',

	plugin  => $PROGNAME,
	shortname => $PROGNAME,
	timeout => 15,
);

$p->add_arg(
    spec => 'id|i=s',
    help => q(-i, --id=STRING),
	required => 1,
);
$p->add_arg(
	spec => 'critical|c=s',
	help => q(critical treshold for ticket expire. [smhd] multiplier maybe used.),
	required => 0,
	default => 24,
);
$p->add_arg(
	spec => 'warning|w=s',
	help => q(warning treshold for ticket expire. [smhd] multiplier maybe used.),
	required => 0,
	default => 48,
);

$p->getopts;

my $verbose = $p->opts->verbose;
my $id = uc $p->opts->id;
my $ua = LWP::UserAgent->new();
$ua->agent($PROGNAME.'/'. $VERSION);
my $url = 'https://www.pilet.ee/pages.php/0402010201';

my $res = $ua->post($url, { id => $id });
unless ($res->is_success) {
	$p->nagios_exit(CRITICAL, $res->status_line);
}

my $root = new HTML::TreeBuilder;
$root->parse($res->content);

my $table = $root->look_down('_tag' => 'td', 'id' => 'contentCell');
my $t = $table->find('p') or $p->nagios_exit(CRITICAL, "Couldn't parse html");
$t = $t->as_text;
print "recv:$t\n" if $verbose;

if ($t =~ /^ID-kaardi nr \Q$id\E omanikuga on seotud järgmised ID-piletid\.$/) {
	print "parse tickets list\n" if $verbose;
	my %map = (
		'Pileti tüüp' => 'type',
		'Kehtivuse lõppaeg' => 'end',
		'Ostmise aeg' => 'purchase',
		'Kehtivuse algusaeg' => 'start',
	);

	use Time::Local qw(timelocal);
	sub parse_date {
		my $str = $_[0];

		# '07.11.2006 23:59:59
		my ($date, $time) = split(/ /, $str);
		my @date = (reverse(split /:/, $time), split(/\./, $date));
		$date[4]--;
		$date[5] -= 1900;
		my $ts = timelocal(@date);
	}

	# gather detailed ticket information
	my @tickets;
	for my $t ($table->look_down('_tag' => 'table',  class => 'content')) {
		my %td = map { $_ = $_->as_text; exists($map{$_}) ? $map{$_} : $_ } $t->find('td');
		push(@tickets, { type => $td{type}, start => parse_date($td{start}), end => parse_date($td{end}) });
		print "add ticket: type: $td{type}; start: $td{start}; end: $td{end}\n" if $verbose;
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
			# ticket in the future, check if it's start period fits to warning range
			if ($t->{start} - $now < $warn) {
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

$p->nagios_exit(OK, "Ticket $id valid") if $t =~ /^Isikul isikukoodiga \Q$id\E on olemas hetkel kehtiv ID-pilet\.$/;
$p->nagios_exit(CRITICAL, "Ticket $id not valid") if $t =~ /^Isikul isikukoodiga \Q$id\E ei ole olemas hetkel kehtivat ID-piletit\.$/;
$p->nagios_exit(WARNING, "No active tickets") if $t =~ /^ID-kaardi nr \Q$id\E omanikuga ei ole seotud ühtegi kehtivat ID-piletit\.$/;
$p->nagios_exit(UNKNOWN, "Need specific ticket ID") if $t =~ /^ID-kaardi nr \Q$id\E omanikuga on seotud järgmised ID-piletid\.$/;
$p->nagios_exit(CRITICAL, "Invalid input") if $t =~ /^Vigane ID-kaardi number või isikukood\.$/;
$p->nagios_exit(UNKNOWN, "Unknown parse status: ".$t);
