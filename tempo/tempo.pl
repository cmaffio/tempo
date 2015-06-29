#!/usr/bin/perl

use DBI;
use Switch;
use DateTime::Format::Strptime;
use HTTP::DAV;
use FindBin qw($Bin);

require "$Bin/tempo.conf";

our $dbh = DBI->connect(          
	"dbi:SQLite:dbname=/home/claudio/bin/tempo/tempo.db", 
	"",                          
	"",                          
	{ RaiseError => 1 },         
) or die $DBI::errstr;

my $azione = shift @ARGV;


switch ($azione) {
	case "start"	{ 
		my $cliente = shift @ARGV;
		my $testo = shift @ARGV;
		apri($dbh, $cliente,$testo); 
	}
	case "stop"	{ 
		my $cliente = shift @ARGV;
		my $testo = shift @ARGV;
		chiudi($dbh, $cliente,$testo); 
	}
	case "oggi"	{ 
		chiudi($dbh); 
		cerca($dbh,'data','NOW'); 
	}
	case "data"	{ 
		my $data = shift @ARGV;
		cerca($dbh,'data',$data); 
	}
	case "cliente"	{ 
		my $cliente = shift @ARGV;
		cerca($dbh,'cliente',$cliente); 
	}
	else		{ 
		print "Errore\n\n" 
	}
}

sub oggi {
	my $db = shift;
	my $quando = shift;

	my $fmt = '%Y-%m-%d %H:%M:%S';
	my $parser = DateTime::Format::Strptime->new(pattern => $fmt);

	my $contaquery = "SELECT COUNT(*) FROM tempo WHERE DATE(tempo) = DATE('$quando') ORDER BY cliente,sessione,rowid";
	my $sth = $db->prepare($contaquery);
	$sth->execute();
	my ($quanti) = $sth->fetchrow();

	my $query = "select * from tempo where date(tempo) = date('$quando') order by cliente,sessione,rowid";
	$sth = $db->prepare($query);  
	$sth->execute();

	my $oldcliente;
	for ($i=0;$i<$quanti;$i+=2) {
		@start = $sth->fetchrow();
		@stop  = $sth->fetchrow();

		if ($oldcliente ne $start[3]) {
			if ($oldcliente ne "") {
				my $ore = int($totale/3600);
				$totale -= $ore*3600;
				my $minuti = int($totale/60);
				$totale -= $minuti*60;
				printf "Tempo totale: %02d:%02d:%02d\n\n",$ore,$minuti,$totale;
				$totale = 0;
			}
			printf "###### %-20s #####\n",$start[3];
		}
		$oldcliente = $start[3];

		print "\t".$start[0]."\tInizio\t".$start[4]."\n";
		print "\t".$stop[0]."\tTermine\t".$stop[4]."\n";

		my $dt1 = $parser->parse_datetime($start[0]) or die;
		my $dt2 = $parser->parse_datetime($stop[0] ) or die;
		my $diff = $dt2 - $dt1;

		$totale += $diff->hours * 3600 + $diff->minutes * 60 + $diff->seconds;

	}
	if ($totale > 0) {
		my $ore = int($totale/3600);
		$totale -= $ore*3600;
		my $minuti = int($totale/60);
		$totale -= $minuti*60;
		printf "Tempo totale: %02d:%02d:%02d\n\n",$ore,$minuti,$totale;
	}

}

sub cerca {
	my $db = shift;

	my $cosa = shift;
	my $param = shift;

	my $fmt = '%Y-%m-%d %H:%M:%S';
	my $parser = DateTime::Format::Strptime->new(pattern => $fmt);

	if ($cosa eq "data") {
		$contaquery = "SELECT COUNT(*) FROM tempo WHERE DATE(tempo) = DATE('$param')";
		$query = "select * from tempo where date(tempo) = date('$param') order by cliente,sessione,rowid";
	} elsif ($cosa eq "cliente") {
		$contaquery = "SELECT COUNT(*) FROM tempo WHERE cliente = '$param'";
		$query = "select * from tempo where cliente = '$param' order by sessione,rowid";
	}

	my $sth = $db->prepare($contaquery);
	$sth->execute();
	my ($quanti) = $sth->fetchrow();

	$sth = $db->prepare($query);  
	$sth->execute();

	my $oldcliente;
	for ($i=0;$i<$quanti;$i+=2) {
		@start = $sth->fetchrow();
		@stop  = $sth->fetchrow();

		if ($oldcliente ne $start[3]) {
			if ($oldcliente ne "") {
				my $ore = int($totale/3600);
				$totale -= $ore*3600;
				my $minuti = int($totale/60);
				$totale -= $minuti*60;
				printf "Tempo totale: %02d:%02d:%02d\n\n",$ore,$minuti,$totale;
				$totale = 0;
			}
			printf "###### %-20s #####\n",$start[3];
		}
		$oldcliente = $start[3];

		print "\t".$start[0]."\tInizio\t".$start[4]."\n";
		print "\t".$stop[0]."\tTermine\t".$stop[4]."\n";

		my $dt1 = $parser->parse_datetime($start[0]) or die;
		my $dt2 = $parser->parse_datetime($stop[0] ) or die;
		my $diff = $dt2 - $dt1;

		$totale += $diff->hours * 3600 + $diff->minutes * 60 + $diff->seconds;

	}
	if ($totale > 0) {
		my $ore = int($totale/3600);
		$totale -= $ore*3600;
		my $minuti = int($totale/60);
		$totale -= $minuti*60;
		printf "Tempo totale: %02d:%02d:%02d\n\n",$ore,$minuti,$totale;
	}

}

sub apri {
	my $db = shift;
	my $cliente = shift;
	my $testo = shift;

	# Ricerca eventuali altre sessioni aperte
	# chiusura eventuali sessioni
	chiudi ($db,'','');

	my $sessquery = "SELECT MAX(sessione) FROM tempo";
	my $sth = $db->prepare($sessquery);  
	$sth->execute();
	my ($sessione) = $sth->fetchrow();
	$sessione+=1;

	my $query = "INSERT INTO tempo VALUES(datetime('now', 'localtime'), 'start', $sessione, '$cliente', '$testo', 0)";
	$db->do($query);

	print "Aperta sessione $sessione per cliente $cliente\n\n";

}

sub chiudi {
	my $db = shift;
	my $cliente = shift;
	my $testo = shift;

	my $idaperto = cerca_aperti ($db);
	if ($idaperto > 0) {
		my $query = "SELECT datetime('now', 'localtime'), tempo, sessione, cliente FROM tempo WHERE ROWID=$idaperto";
		my $sth = $db->prepare($query);
		$sth->execute();
		my ($adesso,$tempo, $sessione, $oldcliente) = $sth->fetchrow();
		$query = "INSERT INTO tempo VALUES(datetime('now', 'localtime'), 'stop', $sessione, '$oldcliente', '$testo', 0)";
		$db->do($query);
		print "Chiusa sessione $sessione del cliente $oldcliente aperta in data $tempo (".diff_time ($tempo, $adesso).")\n";
		ical ($db, $sessione);
	}

}

sub cerca_aperti {
	my $db = shift;

	my $query = "SELECT ROWID,azione FROM tempo ORDER BY ROWID DESC LIMIT 1";
	my $sth = $db->prepare($query);
	$sth->execute();
	my ($ROWID, $azione) = $sth->fetchrow();
	if ($azione eq "start") {
		return $ROWID;
	} else {
		return 0;
	}
}

sub diff_time {
	my $start = shift;
	my $end = shift;

	my $fmt = '%Y-%m-%d %H:%M:%S';
	my $parser = DateTime::Format::Strptime->new(pattern => $fmt);

	my $dt1 = $parser->parse_datetime($start) or die;
	my $dt2 = $parser->parse_datetime($end) or die;

	my $diff = $dt2 - $dt1;

	$differenza = sprintf "%02d:%02d:%02d",$diff->hours,$diff->minutes,$diff->seconds;
	return $differenza;
}

sub ical {
	my $db = shift;
	my $id = shift;


	my $query = "select * from tempo where sessione = $id order by rowid";
	$sth = $db->prepare($query);  
	$sth->execute();

	my @start = $sth->fetchrow();
	my @stop  = $sth->fetchrow();

	my $cliente 	= $start[3];
	my $descrizione	= $start[4];
	my $inizio 	= $start[0];
	my $fine 	= $stop[0];

	my $tempo	= diff_time ($inizio, $fine);

	if ($inizio =~ /(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2}):(\d{2})/) { $inizio_cal = "$1$2$3T$4$5$6"; }
	if ($fine =~ /(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2}):(\d{2})/) { $fine_cal = "$1$2$3T$4$5$6"; }
	
	my $adesso = $fine_cal."Z";

	#print <<FINEICAL
	my $outstr = <<FINEICAL;
BEGIN:VCALENDAR
VERSION:2.0
BEGIN:VTIMEZONE
TZID:Europe/Rome
END:VTIMEZONE
BEGIN:VEVENT
DTSTAMP;VALUE=DATE-TIME:$adesso
CREATED:$adesso
UID: attivita-$id
LAST-MODIFIED;VALUE=DATE-TIME:$adesso
SUMMARY:Attivita' Claudio: $cliente
DTSTART;VALUE=DATE-TIME;TZID=Europe/Zurich:$inizio_cal
DTEND;VALUE=DATE-TIME;TZID=Europe/Zurich:$fine_cal
TRANSP:OPAQUE
CLASS:PUBLIC
DESCRIPTION:$descrizione
CATEGORIES:Attivita'
END:VEVENT
END:VCALENDAR
FINEICAL

	open ICAL, ">/tmp/attivita-$id.ics";
	print ICAL $outstr;
	close ICAL;

	$dav = new HTTP::DAV;
	my $url = "https://cloud.bi.esseweb.eu/remote.php/caldav/calendars/cmaffio/assenze_shared_by_admin";

	$dav->credentials( -user=>"$user",-pass =>"$password", -url =>$url);
	$dav->open( -url=>$url ) or die("Couldn't open $url: " .$dav->message . "\n");

	if ( $dav->put( -local => "/tmp/attivita-$id.ics", -url => $url ) ) {
	} else {
		print "put failed: " . $dav->message . "\n";
	}
	$dav->unlock( -url => $url );
	unlink "/tmp/attivita-$id.ics";
}
