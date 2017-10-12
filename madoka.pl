#!/usr/bin/perl
#
# pirc madoka (version 3.47.9)
#      by cookie_j (cookie@eds.ecip.nagoya-u.ac.jp)
#

$pirc_version = 'madoka 3.47.9';
$pirc_source = 'http://cc.nekomimi.gr.jp/madoka/';

exit if fork;
$mpidp = $$;
while(1) {
  if ($mpidc = fork) {
    local($tmp) = waitpid($mpidc, 0);
  } else {
    &startup;
    &mainloop;
  }
}
exit;

sub mainloop {
  local($Cn, $nfound, $errno, $reason, $rout, $wout, $eout);
  for (;;) {
    &check_mode_o;
    &check_mode_b;
    $nfound = select($rout=$rin, $wout=$win, $eout=$ein, $interval);
    if ($nfound < 0) {
      if ($! == 4) {
	$nfound = 0;
      } else {
	$errno = sprintf("%d", $!);
	&down("Fatal error $errno ($!) in select. exit...\n");
      }
    }
    &now_time;
    if ($lhour != $hour && $no_log ne 'all') {
      if ($lday != $mday) {
	&day;
	$lday = $mday;
      }
      &hour;
      $lhour = $hour;
    }

    if ($Sconnect) {
      if (time - $Stime > $Stimeout) {
        $Stime = time;
	&close_server('dead connection');
      }
    } else {
      if (time - $Sconnecttime > $Sconnecttimeout) {
	$Sconnecttime = time;
	&connect_server;
      }
    }
    next unless $nfound;
    if (vec($rout, $Ln, 1)) {
      &init_client;
      $clientlastaccesstime = time;
    }
    for ($Cn = 0; $Cn <= $maxCn; $Cn++) {
      next unless (vec($rout, $Cn, 1) && vec($Call, $Cn, 1));
      $C = $C[$Cn];
      unless (sysread($C, $tmp, 4096)) {
	$reason = $! ? "$!" : "closed";
	&close_client($Cn, $reason);
      } else {
	$tmp =~ tr/\015/\012/;
	$Cbuf[$Cn] .= $tmp;
	while ((@Cbufline = split(/\r?\n/, $Cbuf[$Cn], 2)) == 2) {
	  $line = $Cbufline[0];
	  $Cbuf[$Cn] = $Cbufline[1];
	  &client($Cn);
	}
	$Cbuf[$Cn] = $Cbufline[0];
      }
      $clientlastaccesstime = time;
    }
    if (vec($rout, $Sn, 1)) {
      unless (sysread(SERVER, $tmp, 4096)) {
	$reason = $! ? "$!" : "closed by server";
	&sendCok("NOTICE $my_nick :*** closed by server $server($reason)\n");
	&close_server("$reason");
      } else {
	$Stime = time;
	$Sbuf .= $tmp;
	while ((@Sbufline = split(/\r?\n/, $Sbuf, 2)) == 2) {
	  $line = $Sbufline[0];
	  $Sbuf = $Sbufline[1];
	  &server;
	}
	$Sbuf = $Sbufline[0];
      }
    }
  }
}
sub startup {
  eval 'use Config';
  eval 'use Socket';
  if ($@) {
    foreach (@INC) {
      require 'sys/socket.ph' if -r "$_/sys/socket.ph";
      require 'netinet/in.ph' if -r "$_/netinet/in.ph";
    }
  }
  $SOCKADDR = 'S n a4 x8';
  $AF_INET = eval { &AF_INET } || 2;
  $PF_INET = eval { &PF_INET } || $AF_INET;
  $SOCK_STREAM = eval { &SOCK_STREAM } || 1;
  $SOL_SOCKET = eval { &SOL_SOCKET };
  $SO_REUSEADDR = eval { &SO_REUSEADDR };
  $SO_KEEPALIVE = eval { &SO_KEEPALIVE };
  $INADDR_ANY = eval { &INADDR_ANY } || "\0\0\0\0";

  $ENV{'LANG'} = 'C';
  $ENV{'LC_TIME'} = 'C';

  &InitList($autojoinchanlist);
  &InitList($automodechanlist);
  &InitList($autokeychanlist);
  &InitList($nojoinchanlist);
  &InitList($log_mail_to);

  &init_pirc;
  &init_var;
  &read_pircrc;
  &open_files;
  &init_server;

  &down("no NICK in .pircrc\n") unless $my_nick;
  &down("no PASSWD in .pircrc\n") unless $passwd;
  &down("no SERVER in .pircrc\n") unless $server;
  &down("Cannot listen to client.\n") unless &listen_client;
  &down("Cannot connect to $sv[-1]($sport[-1]).\n") unless &connect_server;
  &down("Not found: $logdir\n") unless (-d $logdir);
  if ($log_gzip) {
    local(@tmp) = split(/\s+/, $log_gzip);
    &down("no such file: $log_gzip\n") unless (!$tmp[0] || -x $tmp[0]);
  }
  if ($log_mail) {
    local(@tmp) = split(/\s+/, $log_mail);
    &down("no such file: $log_mail\n") unless (!$tmp[0] || -x $tmp[0]);
  }
  &read_pircmodes;
  &daemon_pirc;
}

# init
sub init_pirc {
  ($perl_version = sprintf("%1.5f", $])) =~ s/00$//;;
  srand(time+$$);
  $homedir = $ENV{'HOME'} || $ENV{'LOGDIR'};
  $interval = 1;
  $Sconnecttimeout = 120;
  $Stimeout = 900;
  $Stime = time;
  $Sconnect = 0;
  $svn = 0;
  $maxCn = 256;
  $last_to = '';

  $rin = $win = $ein = '';
  &InitList($chanlist);
  $daemon = 0;
  $logmode = oct(600);
  $taillog = 30;
  $clientlastaccesstime = time;
  while ($_ = shift(@ARGV)) {
    if ($_ eq '-rc') {
      $pircrc = shift(@ARGV);
      $pircrc =~ s/^~\//$homedir\//;
      &down("Cannot find file $pircrc\n") unless -f $pircrc;
    } elsif ($_ eq '-modes') {
      $pircmodes = shift(@ARGV);
      $pircmodes =~ s/^~\//$homedir\//;
      &down("Cannot find file $pircmodes\n") unless -f $pircmodes;
    }
  }
  @_ = getpwuid($<);
  $_[6] =~ s/,.*$//;
  $my_user = $my_nick = $_[0];
  $my_name = $_[6];
  $server = $away_message = $away_nick = $no_away_nick = '';
  $sport = $cport = '6667';
  $fhn = 3;
  $debug_mode = 0;
}
sub read_pircrc {
  $pircrc = './.pircrc' unless -f $pircrc;
  $pircrc = $homedir . '/.pircrc' unless -f $pircrc;
  local(@pircline);
  if (open(PIRCRC, "$pircrc")) {
    @pircline = <PIRCRC>;
    close(PIRCRC);
  } else {
    &down("Cannot open file $pircrc\n");
  }
  foreach (@pircline) {
    next unless /\S/;
    next if /^[\#]/;
    s/\s*\n$//;
    if (/^NICK\s+(.+)/) {
      $my_nick = $1;
      $no_away_nick = $my_nick;
    } elsif (/^NAME\s+(.+)/) {
      $my_name = $1;
    } elsif (/^PORT\s+(\d+)/) {
      $cport = $sport = $1;
    } elsif (/^SPORT\s+(\d+)/) {
      $sport = $1;
    } elsif (/^CPORT\s+(\d+)/) {
      $cport = $1;
    } elsif (/^PASSWD\s+(.+)/) {
      $passwd = $1;
    } elsif (/^AWAYMSG\s+(.+)/) {
      $away_message = $1;
      $my_away_message = $away_message;
    } elsif (/^AWAYNICK\s+(.+)/) {
      $away_nick = $1;
    } elsif (/^AJOIN\s+(on|off)/) {
      $auto_join = $1;
    } elsif (/^AKICK\s+(on|off)/) {
      $auto_kick = $1;
    } elsif (/^AOPMODE\s+(on|off)/) {
      $auto_get = $1;
    } elsif (/^APRIV\s+(on|off)/) {
      $auto_priv = $1;
    } elsif (/^ARMODE\s+(on|off)/) {
      $auto_repair = $1;
    } elsif (/^ATOPIC\s+(on|off)/) {
      $auto_topic = $1;
    } elsif (/^DCCLOG\s+(on|off)/) {
      $dcc_logrec = $1;
    } elsif (/^DCCCLIENT\s+(on|off)/) {
      $dccclient = $1;
    } elsif (/^DCCDIR\s+(.+)/) {
      $dccdir = $1;
      $dccdir =~ s/^~\//$homedir\//;
    } elsif (/^DCCFILE\s+(.+)/) {
      $dcclogfile = $1;
      $dcclogfile =~ s/^~\//$homedir\//;
    } elsif (/^DCCMODE\s+(on|off)/) {
      $get_dcc = $1;
    } elsif (/^DOWNMES\s+(.*)/) {
      $down_mes = $1;
    } elsif (/^KICKPRIV\s+(on|off)/) {
      $kick_priv = $1;
    } elsif (/^LOGDIR\s+(.+)/) {
      $logdir = $1;
      $logdir =~ s/^~\//$homedir\//;
      $logdir .= '/' unless $logdir =~ /\/$/;
    } elsif (/^LOGGZ\s+(.+)/) {
      $log_gzip = $1;
    } elsif (/^LOGMAIL\s+(.+)/) {
      $log_mail = $1;
    } elsif (/^NICKMODE\s+(on|off)/) {
      $nick_mode = $1;
    } elsif (/^RMBAN\s+(\d+)/) {
      $b_count_def = $1;
    } elsif (/^TAILLOG\s+(\d+)/) {
      $taillog = $1;
    } elsif (/^TIMEFMT\s+(\d)/) {
      $timefmt = $1;
      $timefmt = 0 if $timefmt > 2;
    } elsif (/^TOPICLOG\s+(on|off)/) {
      $topic_logrec = $1;
    } elsif (/^TOPICFILE\s+(.+)/) {
      $topiclogfile = $1;
      $topiclogfile =~ s/^~\//$homedir\//;
    } elsif (/^USER\s+(.+)/) {
      $my_user = $1;
    } elsif (/^LOGMAILTO\s+(.+)/) {
      $log_mail_to .= "$1$;";
    } elsif (/^LOGMODE\s+(\d+)/) {
      $logmode = oct($1);
    } elsif (/^OPTION\s+(.+)/) {
      require $1;
    } elsif (/^USERINFO\s+(.+)/) {
      push(@userinfo, $1);
    } elsif (/^DOWN\s+(\d+)(T)?/) {
      local($dt) = $1;
      local($dt1) = $dt % 24;
      if ($2 eq 'T') {
	&now_time;
	$dt = $dt - $hour;
	$dt += 24 if $dt1 <= $hour;
      }
      $down_time = ($dt == 0) ? -1 : $dt + 1;
    } elsif (/^MODECOUNT\s+(\d+)(r)?/) {
      $o_count_def = $1;
      $o_count_random = 1 if $2 eq 'r';
    } elsif (/^(SERVER|SV)\s+(.+)/) {
      local($serv) = $2;
      local($sp) = ($serv =~ /:(\d+)$/);
      $sp = $sport unless $sp;
      push(@sv, $serv);
      push(@sport, $sp);
    } elsif (/^(CHANNEL|NJCHANNEL)\s+(.+)/) {
      local($chan, $mode) = split(/\s+/, $2, 2);
      if (&check_chan($chan)) {
        ($chanr, $chan) = &local_chan($chan);
        if ($chan eq 'PRIV') {
	  $chan_n = 'P';
          $logprefix{'P'} = 'priv';
          $fh{'P'} = 'F1';
        } elsif ($chan eq 'DEBUG') {
          $logprefix{'D'} = 'dbg';
          $fh{'D'} = 'F2';
          $debug_mode = 1;
        } elsif (!&ExistList($autojoinchanlist, $chan)) {
          $chan_n = $chan;
          &AddList($autojoinchanlist, $chan) if /^CHANNEL\s+/;
          &AddList($nojoinchanlist, $chan) if /^NJCHANNEL\s+/;
          $fh{$chan} = 'F' . $fhn++;
	  $automode{$chan} = $mode if $mode;
        }
      }
    } elsif (/^PREFIX\s+(.+)/ && $chan_n && $no_log ne 'all' &&
             !&ExistList($no_log, $chan_n)) {
      local($dt) = $1;
      $logdir  = './' unless $logdir;
      $logdir =~ s/^~\//$homedir\//;
      $logdir .= '/' unless $logdir =~ /\/$/;
      if ($dt =~ /\/$/) {
        local($dir, $prefix) = split(/\//, $dt);
        mkdir("$logdir$dir", oct('0755'));
        $logprefix{$chan_n} = "$logdir$dir/$prefix";
      } else {
        $logprefix{$chan_n} = $dt;
      }
      foreach (keys(%logprefix)) {
        $fh{$chan_n} = $fh{$_} if $logprefix{$_} eq $logprefix{$chan_n};
      }
    } elsif (/^KEY\s+(.+)/ && $chan_n) {
      $autokey{$chan_n} = $1;
    } elsif (/^TOPIC\s+(.+)/ && $chan_n) {
      $autotopic{$chan_n} = $1;
    } elsif (/^CHMAILTO\s+(.+)/ && $chan_n && $logprefix{$chan_n}) {
      $log_mail_to{$chan_n} .= "$1$;";
    } elsif (/^NOLOG$/ && $no_log ne 'all') {
      if ($chan_n) {
	&AddList($no_log, $chan_n);
	delete $logprefix{$chan_n};
	delete $fh{$chan_n};
      } else {
	$no_log = 'all';
      }
    }
  }
  ($server) = ($sv[0] =~ /^([^:]*)(:\d+)?$/);
  $my_nick = $away_nick if $away_nick;
  undef($chan_n);
}
sub init_var {
  $dccdir = $homedir . '/tmp/';
  $get_dcc = 'on';
  $auto_get = 'on';
  $auto_topic = 'off';
  $auto_join = 'on';
  $o_count_def = int(10 + rand(30));
  &InitList($no_log);
  $logdir  = './';
  $auto_priv = 'off';
  $auto_kick = 'off';
  $kick_priv = 'off';
  $auto_repair = 'off';
  $b_count_def = '30';
  $taillog = '30';
  $timefmt = 0;
  $logprefix{'F'} = 'log';
  $logprefix{'P'} = 'log';
  $logprefix{'D'} = 'log';
  $fh{'F'} = 'F0';
  $nick_mode = 'off';
  $dcc_logrec = 'on';
  $topic_logrec = 'off';
  $t_count = 0;
  @userinfo = ();
  $down_time = -1;
  $down_mes = 'auto down';
  $dccclient = 'on';
}
sub open_files {
  &now_time;
  $lday = $mday;
  $lhour = $hour;
  return if $no_log eq 'all';
  &day;
  &hour;
}
sub init_server {
  vec($rin, $Sn, 1) = 0;
  vec($win, $Sn, 1) = 0;
  $Sbuf = '';
  $nickuse = 0;
  $Sconnect = 0;
  $Sr = 0;
  $Sj = 0;
}
sub read_pircmodes {
  $pircmodes = './.pircmodes' unless -f $pircmodes;
  $pircmodes = $homedir . '/.pircmodes' unless -f $pircmodes;
  $pircmodes_change_old{$pircmodes} = $pircmodes_change{$pircmodes} ?
      $pircmodes_change{$pircmodes} : 0;
  $pircmodes_change{$pircmodes} = -M $pircmodes;
  if ($pircmodes_change_old{$pircmodes} > $pircmodes_change{$pircmodes} ||
      $pircmodes_change_old{$pircmodes} == 0) {
    open(MODES, "$pircmodes") || return;
    undef(@modes);
    @modes = <MODES>;
    close(MODES);
    &logF("[d] .pircmodes changed.\n", 'D');
  }
}
sub init_client {
  $seqC++;
  local($C) = 'C' . $seqC;
  accept($C, LISTEN);
  select($C); $| = 1; select(F0);
  local($Cn) = fileno($C);
  $maxCn = $Cn if $Cn > $maxCn;
  $C[$Cn] = $C;
  $Cs[$Cn] = $seqC;
  undef $Cpass[$Cn];
  vec($rin, $Cn, 1) = 1;
  vec($Call, $Cn, 1) = 1;
  vec($Cok, $Cn, 1) = 0;
  local($tmp, $h1, $h2, $h3, $h4);
  ($tmp, $port[$Cn], $h1, $h2, $h3, $h4) =
      unpack('S n C4 x8', getpeername($C));
  $host[$Cn] = "$h1.$h2.$h3.$h4";
  &logF("*** accept $host[$Cn]($port[$Cn])/$Cs[$Cn]\n", 'ALL');
  &chanall;
}

# conect , close
sub daemon_pirc {
  open(STDIN, "/dev/null");
  open(STDOUT, ">&F0");
  open(STDERR, ">&F0");
  $daemon = 1;
  &logF("*** pirc $pirc_version start...\n", 'ALL');
}
sub listen_client {
  local($name, $aliases, $prot) = getprotobyname('tcp');
  unless (socket(LISTEN, $PF_INET, $SOCK_STREAM, $prot)) {
    &logF("socket: $!\n", 'D');
    print STDERR "socket: $!\n";
    return 0;
  }
  if (defined($SOL_SOCKET)) {
    setsockopt(LISTEN, $SOL_SOCKET, $SO_REUSEADDR, 1)
	if defined($SO_REUSEADDR);
    setsockopt(LISTEN, $SOL_SOCKET, $SO_KEEPALIVE, 1)
	if defined($SO_KEEPALIVE);
  }
  if (OSNAME !~ m/linux/i) {
    unless (bind(LISTEN, pack($SOCKADDR, $AF_INET, $cport, $INADDR_ANY))) {
      &logF("bind: $!\n", 'D');
      print STDERR "bind: $!\n";
      print STDERR "Cannot bind tcp socket $cport.\n";
      return 0;
    }
  }
  unless (listen(LISTEN, 5)) {
    &logF("listen: $!\n", 'D');
    print STDERR "listen: $!\n";
    return 0;
  }
  select(LISTEN); $| = 1; select(F0);
  $Ln = fileno(LISTEN);
  vec($rin, $Ln, 1) = 1;
  return 1;
}
sub connect_server {
  local($sp) = $sport[0];
  &sendCok("NOTICE $my_nick :*** trying to connect to $server($sp)\n");
  local($type, $len);
  local($name, $aliases, $prot) = getprotobyname('tcp');
  ($name, $aliases, $sp) = getservbyname($sp, 'tcp') unless $sp =~ /^\d+$/;
  if ($server =~ /^(\d+)\.(\d+)\.(\d+)\.(\d+)$/) {
    $thataddr = sprintf("%c%c%c%c", $1, $2, $3, $4);
  } else {
    ($name, $aliases, $type, $len, $thataddr) = gethostbyname($server);
  }
  local($that) = pack($SOCKADDR, $AF_INET, $sp, $thataddr);
  unless (socket(SERVER, $PF_INET, $SOCK_STREAM, $prot)) {
    &logF("[d] socket: $!\n", 'D');
    return 0;
  }
  $Sn = fileno(SERVER);
  select(SERVER); $| = 1; select(F0);
  if (OSNAME !~ m/linux/i) {
    unless (bind(SERVER, pack($SOCKADDR, $AF_INET, 0, $INADDR_ANY))) {
      &logF("[d] s/bind: $!\n", 'D');
      return 0;
    }
  }
  $Sconnecttime = time;
  unless (connect(SERVER, $that)) {
    &sendCok("NOTICE $my_nick :*** cannot connect..... I'll sleep and try again.\n");
    &sendCok("NOTICE $my_nick :*** If need, type /server <host> [<port>]\n");
    &logF("*** Cannot connect to $server($sp)\n", 'ALL') if $daemon;
    &init_server;
    if ($svn >= 0) {
      push(@sv, shift(@sv));
      push(@sport, shift(@sport));
      $svn = -1 if ++$svn > $#sv;
    }
    ($server) = ($sv[0] =~ /^([^:]*)(:\d+)?$/);
    return 0;
  }

  &logF("*** server $server($sp)\n", 'ALL');
  vec($rin, $Sn, 1) = 1;
  $Sconnect = 1;
  &register_server;
  &join_server;
  return 1;
}
sub register_server {
  $svn = 0;
  $nickuse = 0;
  $Snopong = 1;
  $try_nick = $my_nick;
  &sendS("USER $my_user * * :$my_name\n");
  &sendS("NICK :$try_nick\n");
}
sub join_server {
  local($joinchannels, $autokeys);
  &sendS("AWAY :$my_away_message\n") if $my_away_message;
  foreach $chan (split(/$;/, $autojoinchanlist)) {
    next unless $chan;
    local($chanr, $chanv) = &local_chan($chan);
    if (&check_chan($chanv)) {
      if ($auto_join ne 'off') {
	&AddList($chanlist, $chanv);
	$joinchannels .= ",$chanr";
	$autokeys .= ",$autokey{$chanv}";
      }
    } else {
      &sendCchan("NOTICE $my_nick :BAD channel name($chanv)\n");
      &logF("*** BAD channel name($chanv).\n", 'F');
    }
  }
  $joinchannels =~ s/^,//;
  $autokeys =~ s/^,//;
  &sendS("JOIN $joinchannels $autokeys \n") if $joinchannels;
  $Sj = 1;
}
sub close_server {
  local($reason) = @_;
  close(SERVER);
  &logF("*** server closed ($reason)\n", 'ALL');
  vec($rin, $Sn, 1) = 0;
  $Sconnect = 0;
  local($i, $tmp);
  foreach $chan (split(/$;/, $chanlist)) {
    next unless $chan;
    local($chanr, $chanv) = &local_chan($chan);
    &sendCok(":$my_nick!$machine{$my_nick} PART :$chanr\n");
  }
  if ($svx && $svp) {
    unshift(@sv, $svx);
    unshift(@sport, $svp);
    undef $svx;
    undef $svp;
  } elsif ($svn >= 0) {
    push(@sv, shift(@sv));
    push(@sport, shift(@sport));
    $svn = -1 if ++$svn > $#sv;
  }
  ($server) = ($sv[0] =~ /^([^:]*)(:\d+)?$/);
  &InitList($chanlist);
  &init_server;
  &connect_server unless $Snopong;
}
sub close_client {
  local($Cn, $reason) = @_;
  &logF("*** closed/$Cs[$Cn] ($reason)\n", 'ALL');
  close($C[$Cn]);
  vec($rin, $Cn, 1) = 0;
  vec($Call, $Cn, 1) = 0;
  vec($Cok, $Cn, 1) = 0;
  undef $client_nick[$Cn];
  undef $client_user[$Cn];
  &AddList($chanlist, $last_to) if ($last_to && &DelList($chanlist, $last_to));
  local($tmp) = $maxCn;
  for ($CCn = 0, $no_client = 1; $CCn <= $tmp; $CCn++) {
    next unless vec($Call, $CCn, 1);
    $maxCn = $CCn;
    $no_client = 0;
  }
  if ($no_client == 1) {
    if ($nick_mode eq 'on' && $away_nick && $my_nick ne $away_nick) {
      $no_away_nick = $my_nick;
      &sendS("NICK :$away_nick\n");
      $my_nick = $away_nick;
    }
    if ($my_away_message ne $away_message) {
      &logF("Autoaway: $away_message\n", 'ALL');
      $my_away_message = $away_message;
      &sendS("AWAY :$my_away_message\n");
    }
    if ($DCC_Client_connected == 1) {
      $DCC_Client_connected = 0;
      $get_dcc = 'on';
    }
  }
}

# server
sub server {
  ($from, $where, $command, $rest) =
      ($line =~ /^(:[^! ]*)?(![^ ]*)? *([^ ]+) :?(.*)$/);
  $from =~ s/^://;
  $where =~ s/^!//;
  local($com) = $command;
  $com =~ tr/A-Z/a-z/;
  $machine{$from} = $where;
  local($s_cmd) = "s_$com";
  if (defined(&$s_cmd)) {
    &$s_cmd($from, $rest);
  } else {
    &sendCok("$line\n");
  }
}

# client
sub client {
  local($Cn) = $_[0];
  local($tmp, $command, $rest) = ($line =~ /^(:[^ ]*)? *([^ ]+) *:?(.*)$/);
  return unless $command;
  local($com) = $command;
  $com =~ tr/A-Z/a-z/;
  $rest =~ s/^\s*(.*)\s*$/$1/;
  &logF("[d] com = $command / seq = $Cs[$Cn]\n", 'D');
  unless (vec($Cok, $Cn, 1)) {
    &check_passwd($Cn) if &nopasswd($Cn);
    return;
  }
  $com = 'send' if $com eq 'csend';
  local($c_cmd) = "c_$com";
  &logF("[d] c_cmd = $c_cmd\n", 'D');
  if (defined(&$c_cmd)) {
    &$c_cmd($rest, $Cn);
  } else {
    &sendS("$line\n");
  }
}

# server commands
sub s_topic {
  local($chan, $topic) = split(/ /, $_[1], 2);
  local($chanr, $chanv) = &local_chan($chan);
  $topic =~ s/^://;
  local($topicl) = $topic;
  if ($topicl =~ /\033\$[BI][^\033]*$/ || $topicl =~ /\033[\$\(]?$/) {
    $topicl =~ s/(\$|\033(\()?)$//;
    $topicl .= "\033(B";
  }
  &logF("Topic of channel $chanv by $from: $topicl\n", $chanv);
  $topics{$chanv} = $autotopic{$chanv} = $topic;
  local($topiclogfile) = sprintf("%s%stopic", $logdir, $logprefix{'F'})
      unless $topiclogfile;
  if ($topic_logrec eq 'on') {
    if (open(TOPICLOG, ">>$topiclogfile")) {
      chmod($logmode, $topiclogfile);
      select(TOPICLOG); $| = 1; select(F0);
      &now_time;
      local($tmp) = sprintf("%04d/%02d/%02d %02d:%02d:%02d",
			    $year, $mon, $mday, $hour, $min, $sec);
      print TOPICLOG "$tmp $chanv by $from: $topicl\n";
      close(TOPICLOG);
    }
  }
  $Cchan = $Cchan{$chanv};
  &sendCchan(":$from!$where TOPIC $chanr :$topic\n");
}
sub s_join {
  local($from, $chan) = @_;
  local($chan, $smode) = split(/\007/, $chan) if $chan =~ /\007/;
  local($chanr, $chanv) = &local_chan($chan);
  if ($smode) {
    &logF("+ $from($where) to $chanv with +$smode\n", $chanv);
    &ChangeList($nameslist{$chanv}, $from, "\@$from") if $smode =~ /o/;
    &ChangeList($nameslist{$chanv}, "\+$from", "\@$from") if $smode =~ /o/;
    &ChangeList($nameslist{$chanv}, $from, "+$from") if $smode =~ /v/;
  } else {
    &logF("+ $from($where) to $chanv\n", $chanv);
  }
  if ($from eq $my_nick) {
    $Cchan{$chanv} = '';
    &AddList($chanlist, $chanv);
    &InitList($nameslist{$chanv});
    &AddList($autojoinchanlist, $chanv);
    $Cchan = '';
    if ($smode) {
      &sendCchan(":$from!$where JOIN :$chanr\007$smode\n");
    } else {
      &sendCchan(":$from!$where JOIN :$chanr\n");
    }
    $newtopic = 1;
  } else {
    unless (&ExistList($nameslist{$chanv}, "\+$from") ||
	    &ExistList($nameslist{$chanv}, "\@$from")) {
      &AddList($nameslist{$chanv}, $from);
    }
    $Cchan = $Cchan{$chanv};
    if ($smode) {
      &sendCchan(":$from!$where JOIN :$chanr\007$smode\n");
    } else {
      &sendCchan(":$from!$where JOIN :$chanr\n");
    }
    &logF("[d] from = $from!$where\n", 'D');
    &logF("[d] nlist($chanv) = $nameslist{$chanv}\n", 'D');
    unless ($smode) {
      &logF("[d] op check\n", 'D');
      &read_pircmodes;
      &set_mode($chanv);
    }
  }
}
sub s_part {
  local($from, $chan, $mes) = ($_[0], split(/ :/, $_[1]));
  local($chanr, $chanv) = &local_chan($chan);
  &logF("- $from from $chanv ($mes)\n", $chanv);
  if ($from eq $my_nick) {
    delete $Cchan{$chanv};
    &DelList($chanlist, $chanv);
    delete $nameslist{$chanv};
    &DelList($autojoinchanlist, $chanv);
    if (&ExistList($nojoinchanlist, $chanv) && $logprefix{$chanv}) {
      local($fh) = $fh{$chanv};
      close($fh);
    }
  } else {
    &DelList($nameslist{$chanv}, $from);
    &DelList($nameslist{$chanv}, "\+$from");
    &DelList($nameslist{$chanv}, "\@$from");
    &check_names($chanv);
    &check_mem($from);
  }
  $Cchan = $Cchan{$chanv};
  &sendCchan(":$from!$where PART $chanr :$mes\n");
}
sub s_quit {
  local($from, $mes) = @_;
  unless ($mes) {
    &logF("! $from\n", 'ALL');
  } else {
    &logF("! $from ($mes)\n", 'ALL');
  }
  for ($tmp = 0; $tmp <= $maxCn; $tmp++) {
    vec($Cchan, $tmp, 1) = 1;
  }
  foreach $chan (split(/$;/, $chanlist)) {
    next unless $chan;
    if (&DelList($nameslist{$chan}, $from) ||
	&DelList($nameslist{$chan}, "\+$from") ||
	&DelList($nameslist{$chan}, "\@$from")) {
      &check_names($chan);
      &check_mem($from);
      $Cchan &= $Cchan{$chan};
    }
  }
  &sendCchan(":$from!$where QUIT :$mes\n");
}
sub s_kick {
  local($from, $rest) = @_;
  local($chan, $who, $mes) = ($rest =~ /^([^ ]+) ([^ ]+) :?(.*)$/);
  local($chanr, $chanv) = &local_chan($chan);
  &logF("- $who by $from from $chanv ($mes)\n", $chanv);
  if ($who eq $my_nick) {
    delete $Cchan{$chanv};
    &DelList($chanlist, $chanv);
    delete $nameslist{$chanv};
    delete $topics{$chanv};
    if (&check_chan($chanv)) {
      if ($auto_join ne 'off') {
	&sendS("JOIN $chanr :$autokey{$chanv}\n");
      }
    }
  } else {
    &DelList($nameslist{$chanv}, $who);
    &DelList($nameslist{$chanv}, "\+$who");
    &DelList($nameslist{$chanv}, "\@$who");
    &check_names($chanv);
    &check_mem($who);
  }
  $Cchan = $Cchan{$chanv};
  &sendCchan(":$from!$where KICK $chanr $who :$mes\n");
}
sub s_mode {
  local($from, $rest) = @_;
  local($chanr);
  ($chan, $mode) = split(/ /, $rest, 2);
  ($chanr, $chanv) = &local_chan($chan);
  &logF("Mode by $from: $chanv $mode\n", $chanv);
  $Cchan = $Cchan{$chanv};
  &sendCchan(":$from!$where MODE $chanr $mode \n");
  undef($send_mode);
  while ($mode =~ /\S/) {
    ($list, $mode) = split(/ /, $mode, 2);
    foreach $com (split(//, $list)) {
      if ($com eq '+' || $com eq '-') {
	$flag = $com;
      } else {
	local($mode_cmd) = "mode_$com";
	&$mode_cmd if defined(&$mode_cmd);
      }
    }
  }
  &sendS("MODE $chanr $send_mode \n") if $send_mode;
}
sub s_nick {
  local($from, $nick) = @_;
  if ($from eq $my_nick) {
    &logF("My nick is changed ($from -> $nick)\n", 'ALL');
    $my_nick = $nick;
    $my_nick =~ s/ //g;
    $nickuse = 0;
  } else {
    &logF("$from -> $nick\n", 'ALL');
  }
  for ($tmp = 0; $tmp <= $maxCn; $tmp++) {
    vec($Cchan, $tmp, 1) = 1;
  }
  foreach $chan (split(/$;/, $chanlist)) {
    next unless $chan;
    &ChangeList($nameslist{$chan}, $from, $rest);
    &ChangeList($nameslist{$chan}, "\+$from", "\+$rest");
    &ChangeList($nameslist{$chan}, "\@$from", "\@$rest");
    $Cchan &= $Cchan{$chan};
  }
  $machine{$nick} = $machine{$from};
  &sendCchan(":$from!$where NICK :$nick\n");
  $from =~ s/(\W)/\\$1/g;
  foreach (@naruto) {
    s/ $from / $nick /;
  }
}
sub s_invite {
  local($from, $rest) = @_;
  local($tmp, $chan) = split(/\s:/, $rest, 2);
  local($chanr, $chanv) = &local_chan($chan);
  &logF("Invited by $from: $chanv\n", $chanv);
  if (&ExistList($autojoinchanlist, $chanv)) {
    &sendS("JOIN $chanr :$autokey{$chanv}\n");
  }
  &sendCok(":$from!$where INVITE $my_nick :$chanr\n");
}
sub s_privmsg {
  local($from, $rest) = @_;
  local($chan, $tmp) = ($rest =~ /^([^ ]+) *:?(.*)$/);
  local($chanr, $chanv) = &local_chan($chan);
  local($mes, $ctcpm, $tmp2);
  @ctcpc = (); $n = 0;
  while ($tmp =~ /^([^\001]*)\001([^\001]*)\001(.*)/) {
    $mes .= $1;
    $tmp = $3;
    $ctcpm .= $2 . ' ';
    push (@ctcpc, $2) if &ctcp($chanv, $2);
  }
  $mes .= $tmp;
  &logF("[d] ctcp   = $ctcpm\n", 'D') if $ctcpm;
  if ($mes) {
    local($mesl) = $mes;
    if ($mesl =~ /\033\$[BI][^\033]*$/ || $topicl =~ /\033[\$\(]?$/) {
      $mesl =~ s/(\$|\033(\()?)$//;
      $mesl .= "\033(B";
    }
    if ($chanv =~ /^[\#&%]/ && &ExistList($chanlist, $chanv)) {
      if (&ExistList($nameslist{$chanv}, $from) ||
	  &ExistList($nameslist{$chanv}, "\+$from") ||
	  &ExistList($nameslist{$chanv}, "\@$from")) {
	&logF("<$chanv:$from> $mesl\n", $chanv);
      } else {
	&logF("($chanv:$from) $mesl\n", $chanv);
      }
    } else {
      &logF("=$from= $mesl\n", 'P');
    }
    $Cchan = $Cchan{$chanv};
    &sendCchan(":$from!$where PRIVMSG $chanr :$mes\n");
    return;
  }
  foreach (@ctcpc) {
    $Cchan = $Cchan{$chanv};
    &sendCchan(":$from!$where PRIVMSG $chanr :\001$_\001\n");
  }
}
sub s_notice {
  local($from, $rest) = @_;
  local($chan, $ctcpr, $tmp, $mes);
  ($chan, $mes) = split(/ :/, $rest, 2);
  local($chanr, $chanv) = &local_chan($chan);
  if ($mes =~ /^\001.*\001$/) {
    $mes =~ s/\001//g;
    ($ctcpr, $mes) = split(/\s+/, $mes, 2);
    $tmp = $ctcpr;
    $tmp =~ tr/A-Z/a-z/;
    &sendCok("$line\n");
    return;
  }
  if ($chanv =~ /^[\#&%]/) {
    if (&ExistList($nameslist{$chanv}, $from) ||
	&ExistList($nameslist{$chanv}, "\+$from") ||
	&ExistList($nameslist{$chanv}, "\@$from")) {
      &logF("<$chanv:$from> $mes\n", $chanv);
    } else {
      &logF("($chanv:$from) $mes\n", $chanv);
    }
  } else {
    &logF("=$from= $mes\n", 'P');
  }
  &sendCok(":$from!$where NOTICE $chan :$mes\n");
}
sub s_ping {
  local($from, $rest) = @_;
  &sendCok("PING :$rest\n");
  &sendS("PONG :$rest\n");
}
sub s_pong {
  local($from, $rest) = @_;
  &sendCok(":$from PONG $from :$rest\n");
}
sub s_error {
  local($from, $rest) = @_;
  local($reason) = ($rest =~ /\((.*)\)$/);
  &close_server($reason);
  &sendCok("ERROR :$rest\n");
}
sub s_kill {
  local($tmp, $tmp, $reason) = ($rest =~ /^([^ ]+) *:?(.*)$/);
  &logF("Killed by $from: $reason\n", 'P');
  &sendCok("$line\n");
}
sub s_001 {
  local($from, $nick) = @_;
  $nick =~ s/^(.*) :.*/$1/;
  &logF("[d] 001 nick = $nick\n", 'D');
  $server = $from;
  $Sr = 1;
  &join_server unless $Sj;
  $try_nick = '';
  if ($my_nick ne $nick) {
    &sendCok(":$my_nick!$machine{$my_nick} NICK :$nick\n");
    $my_nick = $nick;
  }
}
sub s_315 {
  local($from, $rest) = @_;
  local($rest) = ($rest =~ /^[^ ]+ ([^ ]+) :.*$/);
  &sendCok(":$from 315 $my_nick $rest :End of /WHO list.\n");
}
sub s_318 {
  local($from, $rest) = @_;
  local($rest) = ($rest =~ /^[^ ]+ ([^ ]+) :.*$/);
  &sendCok(":$from 318 $my_nick $rest :End of /WHOIS list.\n");
}
sub s_319 {
  local($from, $rest) = @_;
  local($nick, $tmp, $chan) = split(/ /, $rest, 3);
  local($mes);
  $chan =~ s/^://;
  foreach (split(/ /, $chan)) {
    if (/:\*\.JP$/i) {
      s/:\*\.JP$/:\*\.jp/i;
    }
    $mes .= "$_ ";
  }
  &sendCok(":$from 319 $nick $tmp :$mes\n");
}
sub s_322 {
  local($from, $rest) = @_;
  local($nick, $chan, $num, $topic) = split(/\s+/, $rest, 4);
  local($chan, $tmp) = &local_chan($chan);
  &sendCok(":$from 322 $nick $chan $num $topic\n");
}
sub s_323 {
  local($from, $rest) = @_;
  &sendCok(":$from 323 $my_nick :End of /LIST\n");
}
sub s_332 {
  local($from, $rest) = @_;
  local($nick, $chan, $topic) = split(/ /, $rest, 3);
  local($chanr, $chanv) = &local_chan($chan);
  $topic =~ s/^://;
  if (!$topic && $autotopic{$chanv}) {
    &sendS("TOPIC $chanr :$autotopic{$chanv}\n");
    $topics{$chanv} = $autotopic{$chanv};
  } else {
    $topics{$chanv} = $topic;
  }
  $newtopic = 0;
  &sendCok(":$from 332 $my_nick $chan :$topic\n");
}
sub s_353 {
  local($from, $rest) = @_;
  local($tmp, $tmp2, $chanr);
  ($tmp, $tmp, $chan, $list) = split(/ /, $rest, 4);
  ($chanr, $chanv) = &local_chan($chan);
  unless (&ExistList($chanlist, $chanv)) {
    $tmp2 = $chanv; $tmp2 =~ s/(\W)/\\$1/g;
    ($tmp) = $chanlist =~ /$;($tmp2)$;/i;
    &logF("[d] old = $tmp\n", 'D');
    &logF("[d] new = $chanv\n", 'D');
    if ($tmp) {
      &ChangeList($chanlist, $tmp, $chanv);
      $nameslist{$chanv} = $nameslist{$tmp}; delete $nameslist{$tmp};
      $Cchan{$chanv} = $Cchan{$tmp}; delete $Cchan{$tmp};
      $fh{$chanv} = $fh{$tmp}; delete $fh{$tmp};
      $logprefix{$chanv} = $logprefix{$tmp}; delete $logprefix{$tmp};
      $topics{$chanv} = $topics{$tmp}; delete $topics{$tmp};
      $autokey{$chanv} = $autokey{$tmp}; delete $autokey{$tmp};
      $automode{$chanv} = $automode{$tmp}; delete $automode{$tmp};
      $autotopic{$chanv} = $autotopic{$tmp}; delete $autotopic{$tmp};
    }
  }
  $list =~ s/^://;
  local($mem) = $list;
  &make_list;
  &sendCok(":$from 353 $my_nick = $chanr :$mem\n");
}
sub s_365 {
  local($from, $rest) = @_;
  local($rest) = ($rest =~ /^[^ ]+ ([^ ]+) :.*$/);
  &sendCok(":$from 365 $my_nick $rest :End of /LINKS list.\n");
}
sub s_366 {
  local($from, $rest) = @_;
  $lastnameschannel = '';
  local($nick, $chan, $rest) = split(/ /, $rest, 3);
  local($chanr, $chanv) = &local_chan($chan);
  if ($auto_topic eq 'on' && $newtopic && $topics{$chanv} =~ /\S/) {
    &sendS("TOPIC $chanr :$topics{$chanv}\n");
  }
  if ($automode{$chanv} && &ExistList($nameslist{$chanv}, "\@$my_nick")) {
    &sendS("MODE $chanr $automode{$chanv} \n");
  }
  undef($newtopic);
  &sendCok(":$from 366 $my_nick $chanr :End of /NAMES list.\n");
}
sub s_433 {
  local($from, $rest) = @_;
  local($tmp, $try_nick) = split(/\s/, $rest);
  &sendCok(":$from 433 $my_nick $try_nick :Nickname is already in use.\n");
  &sendCok("NOTICE $my_nick :Nickname($try_nick) is already in use.\n");
  unless ($Sr) {
    &logF("[d] Sr = $Sr try = $try_nick nickuse = $nickuse\n",'D');
    if (++$nickuse < 6) {
      $try_nick .= '_';
      $try_nick =~ s/^.*(.........)/$1/;
      &sendCok("NOTICE $my_nick :*** nick trying again ($try_nick)\n");
    }
    &register_server;
    &join_server;
    return 1;
  }
}
sub s_437 {
  ($try_nick) = ($rest =~ /^[^ ]+ ([^ ]+) :.*$/);
  &sendCok(":$from 437 $my_nick $try_nick :Nick/channel is temporarily unavailable\n");
  if (!$Sr && $try_nick !~ /^[\#\&\+]/) {
    &logF("[d] Sr = $Sr try = $nc nickuse = $nickuse\n",'D');
    if (++$nickuse < 6) {
      $try_nick .= '_';
      $try_nick =~ s/^.*(.........)/$1/;
      &sendCok("NOTICE $my_nick :*** nick trying again ($try_nick)\n");
    }
    &register_server;
    &join_server;
    return 1;
  }
}
sub s_451 {
  &sendCchan("NOTICE $my_nick :You have not registed.\n");
}
sub s_465 {
  &logF("You are banned from $server\n", 'ALL');
}
sub s_471 {
  local($from, $rest) = @_;
  local($chan) = ($rest =~ /^[^ ]+ ([^ ]+) :.*$/);
  local($chanr, $chanv) = &local_chan($chan);
  &DelList($chanlist, $chanv);
  &sendCok(":$from 471 $my_nick $chanr :Cannot join channel (+l)\n");
}
sub s_472 {
  local($from, $rest) = @_;
  local($char) = ($rest =~ /^[^ ]+ ([^ ]+) :.*$/);
  &sendCok(":$from 472 $my_nick $char :is unknown mode char to me\n");
}
sub s_473 {
  local($from, $rest) = @_;
  local($chan) = ($rest =~ /^[^ ]+ ([^ ]+) :.*$/);
  local($chanr, $chanv) = &local_chan($chan);
  &DelList($chanlist, $chanv);
  &sendCok(":$from 473 $my_nick $chanr :Cannot join channel (+i)\n");
}
sub s_474 {
  local($from, $rest) = @_;
  local($chan) = ($rest =~ /^[^ ]+ ([^ ]+) :.*$/);
  local($chanr, $chanv) = &local_chan($chan);
  &DelList($chanlist, $chanv);
  &sendCok(":$from 474 $my_nick $chanr :Cannot join channel (+b)\n");
}
sub s_475 {
  local($from, $rest) = @_;
  local($chan) = ($rest =~ /^[^ ]+ ([^ ]+) :.*$/);
  local($chanr, $chanv) = &local_chan($chan);
  &DelList($chanlist, $chanv);
  &sendCok(":$from 475 $my_nick $chanr :Cannot join channel (+k)\n");
}

# modes
sub mode_a {
}
sub mode_b {
  local($ban, $bang);
  ($ban, $mode) = split(/ /, $mode, 2);
  $bang = $ban;
  $bang =~ s/(\W)/\\$1/g;
  $bang =~ s/\\\*/.*/g;
  $bang =~ s/\\\?/./g;
  &logF("[d] ban  = $ban\n", 'D');
  if ($flag eq '+') {
    if ("$my_nick!$machine{$my_nick}" =~ /^$bang$/i) {
      $send_mode .= ' -b ' . $ban;
    }
  }
}
sub mode_i {
}
sub mode_k {
  local($key);
  ($key, $mode) = split(/ /, $mode, 2);
  if ($flag eq '+') {
    $autokey{$chanv} = $key;
  } else {
    delete $autokey{$chanv};
  }
}
sub mode_l {
  local($num);
  if ($flag eq '+') {
    ($num, $mode) = split(/ /, $mode, 2);
  }
}
sub mode_m {
}
sub mode_o {
  local($nick);
  ($nick, $mode) = split(/ /, $mode, 2);
  &logF("[d] nick(o) = $nick\n", 'D');
  &logF("[d] mode(o) = $mode\n", 'D');
  if ($flag eq '+') {
    &ChangeList($nameslist{$chanv}, $nick, "\@$nick");
    &ChangeList($nameslist{$chanv}, "\+$nick", "\@$nick");
  } else {
    &ChangeList($nameslist{$chanv}, "\@$nick", $nick);
  }
}
sub mode_s {
}
sub mode_t {
}
sub mode_v {
  local($nick);
  ($nick, $mode) = split(/ /, $mode, 2);
  if ($flag eq '+') {
    &ChangeList($nameslist{$chanv}, $nick, "\+$nick");
  } else {
    &ChangeList($nameslist{$chanv}, "\+$nick", $nick);
  }
}

# client commands
sub c_quit {
  local($tmp, $Cn) = @_;
  &close_client($Cn, "Disconnect client:$Cn");
}
sub c_ping {
  local($tmp, $Cn) = @_;
  &sendS("PING :PIRC-$Cn-PING-$tmp\n");
}
sub c_pong {
}
sub c_join {
  local($chan, $key) = split(/\s+/, $_[0]);
  local($chanr, $chanv) = &local_chan($chan);
  unless (&check_chan($chanv)) {
    &sendC("NOTICE $my_nick :*** BAD channel name($chanv).\n");
    return;
  }
  $autokey{$chanv} = $key if $key =~ /\S/;
  &sendS("JOIN $chanr :$autokey{$chanv}\n");
}
sub c_part {
  local($chan, $mes) = split(/ :/, $_[0]);
  local($chanr, $chanv) = &local_chan($chan);
  &sendS("PART $chanr :$mes\n");
}
sub c_privmsg {
  local($chan, $mes) = ($_[0] =~ /^([^ ]+) *:?(.*)$/);
  local($chanr, $chanv) = &local_chan($chan);
  $last_to = $chanv if $chanv =~ /^[\#&%]/;
  $mes =~ s/\001COMMENT[^\001]*\001//gi;
  next unless $mes;
  if ($mes =~ /\001ACTION([^\001]*)\001/) {
    &logF(">$chanv:$my_nick< *ACTION* $my_nick$1\n", $chanv);
  } elsif ($chanv =~ /^[\#&%]/) {
    &logF(">$chanv:$my_nick< $mes\n", $chanv);
  } else {
    &logF(">$chanv< $mes\n", 'P');
  }
  $Cchan = $Cchan{$chanv};
  &sendCchan2(":$my_nick PRIVMSG $chanr :$mes\n");
  &sendS("$line\n");
}
sub c_nick {
  local($nick, $Cn) = @_;
  if (!$Sr && $my_nick ne $nick) {
    &sendCok(":$my_nick!$machine{$my_nick} NICK :$nick\n");
    $my_nick = $nick;
    return;
  }
  $try_nick = $nick;
  &sendS("NICK :$try_nick\n");
}
sub c_away {
  local($mes, $Cn) = @_;
  if ($mes =~ /^ *$/) {
    &logF("Away off\n", 'ALL');
    $my_away_message = '';
  } else {
    &logF("Away: $rest\n", 'ALL');
    $my_away_message = $mes;
  }
  &sendS("$line\n");
}
sub c_who {
  &sendS("$line\n");
}
sub c_links {
  &sendS("$line\n");
}
sub c_names {
  local($chan, $Cn) = @_;
  local($chanr, $chanv) = &local_chan($chan);
  &sendS("NAMES :$chanr\n");
}
sub c_list {
  local($chan, $Cn) = @_;
  local($chanr, $chanv) = &local_chan($chan);
  &sendS("LIST :$chanr\n");
}

## pirc commands
sub c_bye {
  local($mes, $Cn) = @_;
  &logF("*** Bye($mes)/$Cs[$Cn]\n", 'ALL');
  &sendS("QUIT :$mes\n");
  close(LISTEN);
  close(SERVER);
  &sendCok("ERROR :Closing Link: $my_nick (pirc down/$mes)\n");
  for ($Cnn = 0; $Cnn <= $maxCn ; $Cnn++) {
    next unless vec($Call, $Cnn, 1);
    close($C[$Cnn]);
  }
  &down('');
}
sub c_server {
  local($tmp, $Cn) = @_;
  ($svx, $svp) = split(/[:\s]+/, $tmp);
  $svp = $sport unless $svp;
  &sendC("NOTICE $my_nick :*** old server has been closed.\n");
  $Snopong = 0;
  &close_server('change server');
}

## commnad of madoka 3.0 after
sub c_send {
  local($rest, $Cn) = @_;
  local($who, $sz, $nm, $sv, $pt);
  local($chan, $file) = split(/\s+/, $rest);
  $file =~ s/^~\//$homedir\//;
  unless (-r $file) {
    &sendC("NOTICE $my_nick :cannot read $file\n");
    return;
  }
  if ($chan =~ /^[\#%&]/) {
    ($chanr, $chan) = &local_chan($chan);
    $chan = $nameslist{$chan};
    $chan =~ s/\@//g;
    $chan =~ s/\+//g;
  }
  foreach $who (split(/$;/, $chan)) {
    next if ($who eq $my_nick || !$who);
    $dcclogfile = sprintf("%s%sdcc", $logdir, $logprefix{'F'})
	unless $dcclogfile;
    if ($dcc_logrec eq 'on') {
      if (open(DCCLOG, ">>$dcclogfile")) {
	chmod($logmode, $dcclogfile);
	select(DCCLOG); $| = 1; select(F0);
	&now_time;
	$sz = -s $file;
	printf DCCLOG "%04d/%02d/%02d %02d:%02d:%02d[SEND] " .
	    "$file($sz bytes)\n        to $who!$machine{$who}\n",
	    $year, $mon, $mday, $hour, $min, $sec;
	close(DCCLOG);
      }
    }
    unless (fork) {
      unless (fork) {
	$sz = -s $file;
	$nm = substr($file, rindex($file, '/') + 1);
	if (&dcc_listen) {
	  &sendS("PRIVMSG $who :\001DCC SEND $nm $sv $pt $sz\001\n");
	  &sendC(":$my_nick!$machine{$my_nick} PRIVMSG $who :\001DCC SEND $nm $sv $pt $sz\001\n");
	  &logF(">$who< \001DCC SEND $nm $sv $pt $sz\001\n", 'P');
	  alarm 600;
	  accept(REMOTE, SV);
	  close(SV);
	  alarm 0;
	  select(REMOTE); $| = 1; select(F0);
	  &logF("*** DCC send($nm) to $who start.\n", 'P');
	  &sendC("NOTICE $my_nick :DCC send($nm) to $who start.\n");
	  unless (&dcc_send($who)) {
	    &logF("*** DCC send($nm) to $who failed.\n", 'P');
	    &sendC("NOTICE $my_nick :DCC send($nm) to $who failed.\n");
	  }
	} else {
	  &logF("*** DCC listen failed.\n", 'P');
	  &sendC("NOTICE $my_nick :DCC listen failed.\n");
	}
	exit 0;
      }
      exit 0;
    }
    wait;
  }
}
sub c_get {
  local($tmp, $Cn) = @_;
  return if (!$nm || $dccclient eq 'on');
  unless (fork) {
    unless (fork) {
      if (&dcc_connect) {
	&logF("*** DCC get($nm) from $fr start.\n", 'P');
	&sendCchan("NOTICE $my_nick :DCC get($nm) from $fr start.\n");
	unless (&dcc_get) {
	  &logF("*** DCC get($nm) from $fr failed.\n", 'P');
	  &sendCchan("NOTICE $my_nick :DCC get($nm) from $fr failed.\n");
	}
      } else {
	&logF("*** DCC connect failed.\n", 'P');
	&sendCchan("NOTICE $my_nick :DCC connect failed.\n");
      }
      $nm = '';
      exit 0;
    }
    exit 0;
  }
  wait;
}
sub c_pid {
  &sendC("NOTICE $my_nick :pid: $$ / ppid: $mpidp\n");
}
sub c_var {
  local($tmp, $Cn) = @_;
  local($com, $arg) = split(/\s+/, $tmp);
  $com =~ tr/A-Z/a-z/;
  local($var_cmd) = "var_$com";
  &logF("[d] var = $com\n", 'D');
  &$var_cmd($arg) if defined(&$var_cmd);
}

### debug commands
sub c_debug {
  local($rest, $Cn) = @_;
  if ($rest == 1) {
    $debug_mode = 1;
    $fh{'D'} = 'F2';
    $logprefix{'D'} = 'dbg';
    &now_time;
    &open_log('D');
    chmod($logmode, $logfile{'D'});
    select(F2); $| = 1;
    printf F2 "%04d/%02d/%02d %02d:%02d:%02d\n", $year, $mon, $mday, $hour, $min, $sec;
    select(F0); $| = 1;
  } elsif ($rest == 0) {
    $debug_mode = 0;
    close(F2);
    delete $fh{'D'};
  }
  &sendC("NOTICE $my_nick :debug mode is $debug_mode\n");
}
sub c_print {
  local($com, $Cn) = @_;
  local($tmp) = eval($com);
  &sendC("NOTICE $my_nick : $tmp\n");
}

## end of madoka 3.x command

sub c_passwd {
  local($tmp, $Cn) = @_;
  $passwd = $tmp if $tmp;
}
sub c_chanall {
  &chanall;
  &mychan;
}
sub c_chan {
  local($chan, $Cn) = @_;
  local($chanv);
  if (defined($Cchan{$chan})) {
    foreach $chan (split(/$;/, $chanlist)) {
      next unless $chan;
      vec($Cchan{$chan}, $Cn, 1) = 1;
    }
    vec($Cchan{$chan}, $Cn, 1) = 0;
    &mychan;
  } else {
    &sendC(":PIRC 442 $my_nick $rest :You're not on channel $chan.\n");
  }
}
sub c_chanp {
  local($chan, $Cn) = @_;
  if (defined($Cchan{$chan})) {
    vec($Cchan{$chan}, $Cn, 1) = 0;
    &mychan;
  } else {
    &sendC(":PIRC 442 $my_nick $rest :You're not on channel $chan.\n");
  }
}
sub c_chanm {
  local($chan, $Cn) = @_;
  if (defined($Cchan{$chan})) {
    vec($Cchan{$chan}, $Cn, 1) = 1;
    &mychan;
  } else {
    &sendC(":PIRC 442 $my_nick $rest :You're not on channel $chan.\n");
  }
}
sub c_mychan {
  &mychan;
}
sub c_mynames {
  &mynames;
}
sub c_myinfo {
  &sendC("NOTICE $my_nick :pirc: $pirc_version\n");
  &sendC("NOTICE $my_nick :nick: $my_nick\n");
  &sendC("NOTICE $my_nick :user: $my_user\n");
  &sendC("NOTICE $my_nick :name: $my_name\n");
  &sendC("NOTICE $my_nick :away: $my_away_message\n") if $my_away_message;
  &sendC("NOTICE $my_nick :server: $Sn $server($sport[0])\n") if $Sconnect;
  for ($CCn = 0; $CCn <= $maxCn; $CCn++) {
    next unless vec($Call, $CCn, 1);
    &sendC("NOTICE $my_nick :client: $CCn $Cs[$Cnn]" .
	   "$host[$CCn]($port[$CCn])\n");
  }
  &sendC("NOTICE $my_nick :autoaway nick: $away_nick\n") if $away_nick;
  &sendC("NOTICE $my_nick :autoaway message: $away_message\n")
      if $away_message;
  &mychan;
  &autojoins;
  &automodes;
  &autokeys;
}
sub c_amsg {
  local($mes, $Cn) = @_;
  if ($rest =~ /^ *$/) {
    $away_message = '';
  } else {
    $away_message = $mes;
  }
}
sub c_anick {
  local($nick, $Cn) = @_;
  if ($rest =~ /^ *$/) {
    $away_nick = '';
  } else {
    $away_nick = $nick;
    $away_nick =~ s/ //g;
  }
}
sub c_autojoins {
  &autojoins;
}
sub c_automodes {
  &automodes;
}
sub c_automode {
  local($tmp, $Cn) = @_;
  local($chan, $mode) = ($tmp =~ /^([^ ]+) *([^ ]*)$/);
  local($chanr, $chanv) = &local_chan($chan);
  if (&check_chan($chanv)) {
    &DelList($automodechanlist, $chanv);
    delete $automode{$chanv};
    if ($mode) {
      &AddList($automodechanlist, $chanv);
      $automode{$chanv} = $mode;
    }
  }
}
sub c_autokeys {
  &autokeys;
}
sub c_autokey {
  local($tmp, $Cn) = @_;
  local($chan, $key) = ($tmp =~ /^([^ ]+) *([^ ]*)$/);
  local($chanr, $chanv) = &local_chan($chan);
  if (&check_chan($chanv)) {
    &DelList($autokeychanlist, $chanv);
    delete $autokey{$chanv};
    if ($key) {
      &AddList($autokeychanlist, $chanv);
      $autokey{$chanv} = $key;
    }
  }
}
sub c_notice {
  local($rest, $Cn) = @_;
  local($from, $rest) = split(/ /, $rest, 2);
  $rest =~ s/[\001:]//g;
  &logF("[d] from = $from\n", 'D');
  &logF("[d] rest = $rest\n", 'D');
  &sendS("$line\n");
}

## nopasswd
sub nopasswd {
  local($Cn) = @_;
  local($where, $com, $arg) = ($line =~ /^(:[^ ]*)? *([^ ]+) :?(.+)$/);
  &logF("[d] nopasswd = $line\n", 'D');
  if ($com =~ /^pass/i) {
    $Cpass[$Cn] = $arg;
    return 0;
  } elsif ($com =~ /^user/i) {
    $client_user[$Cn] = $arg;
    return 1 if ($client_nick[$Cn] && $Cpass[$Cn]);
    return 0;
  } elsif ($com =~ /^nick/i) {
    $client_nick[$Cn] = $arg;
    return 1 if ($client_user[$Cn] && $Cpass[$Cn]);
    return 0;
  }
  &sendC(":$server 451 * :You have not registered.\n");
  return 0;
}
sub check_passwd {
  local($Cn) = @_;
  if ($Cpass[$Cn] ne $passwd) {
    &sendC(":$server 464 $client_nick[$Cn] :Password Incorrect.\n");
    &sendC("ERROR :Closing Link: $client_nick[$Cn] (Bad Password)\n");
    &close_client($Cn, 'bad password');
    return;
  }
  vec($Cok, $Cn, 1) = 1;
  &logF("*** password/$Cs[$Cn]\n", 'ALL');
  &sendC(":$server 001 $my_nick :Welcome to the Internet Relay Network $my_nick\n");
  &sendC(":$server 376 $client_nick[$Cn] :End of /MOTD command.\n");
  &sendC(":$client_nick[$Cn] NICK :$my_nick\n");
  if ($Sconnect) {
    &taillog;
    &mynames2;
  } else {
    &sendC("NOTICE $my_nick :*** Now, no server connection.\n");
  }
  &sendC(":PIRC 301 $my_nick $my_nick :$my_away_message\n")
      if $my_away_message;
  if ($nick_mode eq 'on' && $my_nick ne $no_away_nick) {
    $my_nick = $no_away_nick;
    &sendS("NICK :$my_nick\n");
  }
  if ($my_away_message) {
    &logF("Autoaway off\n", 'ALL');
    $my_away_message = '';
    &sendS("AWAY :\n");
  }
  if ($get_dcc eq 'on' && $dccclient eq 'on') {
    $get_dcc = 'off';
    $DCC_Client_connected = 1;
  }
}

## var
sub onoff {
  local($onoff, $rest) = @_;
  if ($onoff eq 'on' || $onoff eq 'off') {
    return $onoff;
  }
  return $rest;
}
sub var_dccdir {
  local($dir) = @_;
  if ($dir =~ /\S/) {
    if (-d $dir) {
      $dccdir = $dir;
      $dccdir .= '/' unless $dccdir =~ /\/$/;
    } else {
      &sendC("NOTICE $my_nick :No such directory: $dir\n");
    }
  }
  &sendC("NOTICE $my_nick :DCC directory: $dccdir\n");
}
sub var_dccclient {
  $dccclient = &onoff(@_, $dccclient);
  &sendC("NOTICE $my_nick :DCC message to client: $dccclient\n");
}
sub var_amsg {
  local($mes) = @_;
  if ($mes =~ /^ *$/) {
    $away_message = '';
  } else {
    $away_message = $mes;
  }
}
sub var_anick {
  local($nick) = @_;
  if ($nick =~ /^ *$/) {
    $away_nick = '';
  } else {
    $away_nick = $nick;
    $away_nick =~ s/ //g;
  }
  &sendC("NOTICE $my_nick :Your away nick: $away_nick\n");
}
sub var_autodcc {
  $get_dcc = &onoff(@_, $get_dcc);
  &sendC("NOTICE $my_nick :DCC autoget mode: $get_dcc\n");
}
sub var_autoget {
  $auto_get = &onoff(@_, $auto_get);
  &sendC("NOTICE $my_nick :channel operater auto get mode: $auto_get\n");
}
sub var_autotopic {
  $auto_topic = &onoff(@_, $auto_topic);
  &sendC("NOTICE $my_nick :auto topic mode: $auto_topic \n");
}
sub var_autojoin {
  $auto_join = &onoff(@_, $auto_join);
  &sendC("NOTICE $my_nick :auto join mode: $auto_join\n");
}
sub var_ircname {
  $my_name = $rest if $rest;
  &sendC("NOTICE $my_nick :your irc name: $my_name\n");
}
sub var_ircuser {
  $my_user = $_[0];
  &sendC("NOTICE $my_nick :your ID: $my_user\n");
}
sub var_log {
  local($tmp, $chan) = &local_chan($_[0]);
  local($chans) = $no_log;
  local($no_log_chan);
  &logF("*** log mode $chan \n", 'F') if $no_log ne $chans;
  foreach (split(/$;/, $no_log)) {
    $no_log_chan .= " $_";
  }
  &sendC("NOTICE $my_nick :no logging channel: $no_log_chan\n");
}
sub var_opcount {
  local($rest) = @_;
  $o_count_def = $rest if $rest;
  &sendC("NOTICE $my_nick :op counter: $o_count_def\n");
}
sub var_apriv {
  $auto_priv = &onoff(@_, $auto_priv);
  &sendC("NOTICE $my_nick :auto priv mode: $auto_priv\n");
}
sub var_kpriv {
  $kick_priv = &onoff(@_, $kick_priv);
  &sendC("NOTICE $my_nick :auto priv(for kick)mode: $kick_priv\n");
}
sub var_akick {
  $auto_kick = &onoff(@_, $auto_kick);
  &sendC("NOTICE $my_nick :auto kick mode: $auto_kick\n");
}
sub var_rmban {
  local($rest) = @_;
  $b_count_def = $rest if $rest;
  &sendC("NOTICE $my_nick :remove ban time: $b_count_def\n");
}
sub var_nickmode {
  $nick_mode = &onoff(@_, $nick_mode);
  &sendC("NOTICE $my_nick :Nick mode: $nick_mode\n");
}
sub var_dcclog {
  $dcc_logrec = &onoff(@_, $dcc_logrec);
  &sendC("NOTICE $my_nick :dcc log record mode: $dcc_logrec\n");
}
sub var_topiclog {
  $topic_logrec = &onoff(@_, $topic_logrec);
  &sendC("NOTICE $my_nick :topic log record mode: $topic_logrec\n");
}
sub var_down {
  local($num) = @_;
  $down_time = $num if ($num > 0 && $num % 1 == 0);
  &sendC("NOTICE $my_nick :madoka will restart about $down_time hour(s) after .\n");
}

## ctcp
sub ctcp {
  local($chan, $mes) = @_;
  local($cmd, $mes) = split(/\s/, $mes, 2);
  local($cmdo, $ctcpf) = ($cmd, 0);
  $cmd =~ tr/A-Z/a-z/;
  local($ctcp_cmd) = "ctcp_$cmd";
  ($chanr, $chanv) = &local_chan($chan);
  &logF("[d] chan(ctcp) = $chanv\n", 'D');
  if (defined(&$ctcp_cmd)) {
    if ($t_count < 1) {
      $ctcpf = 1 unless (($get_dcc eq 'on' || $get_dcc eq 'off' &&
			  $dccclient eq 'off') && $cmd eq 'dcc');
    }
    &$ctcp_cmd($mes);
  } else {
    &sendCchan("NOTICE $my_nick :$cmdo\@$from: $mes\n");
  }
  if ($chanr eq $my_nick) {
    &logF("Query from $from: $cmd $mes\n", 'P');
  } else {
    &logF("Query from $from($chanv): $cmd $mes\n", 'P');
  }
  return $ctcpf;
}

### ctcp commands
sub ctcp_action {
  local($mes) = $_[0];
  if ($mes) {
    if ($chanr =~ /^[\#&%]/) {
      if (&ExistList($nameslist{$chanv}, $from)) {
	&logF("<$chanv:$from> *ACTION* $from $mes\n", $chanv);
      } else {
	&logF("($chanv:$from) *ACTION* $from $mes\n", $chanv);
      }
    } else {
      &logF("=$from= *ACTION* $from $mes\n", 'P');
    }
  }
}
sub ctcp_version {
  &sendS("NOTICE $from :\001VERSION pirc $pirc_version in perl $perl_version:\001\n");
}
sub ctcp_clientinfo {
  &sendS("NOTICE $from :\001CLIENTINFO : ACTION " .
	 "CLIENTINFO DCC ECHO FINGER PING SOURCE " .
	 "TIME USERINFO VERSION\001\n");
}
sub ctcp_userinfo {
  foreach (@userinfo) {
    &sendS("NOTICE $from :\001USERINFO :$_\001\n");
  }
}
sub ctcp_source {
  &sendS("NOTICE $from :\001SOURCE $pirc_source\001\n");
}
sub ctcp_finger {
  local($total) = time - $clientlastaccesstime;
  local($sec) = $total;
  local($min) = int($sec / 60); $sec -= $min * 60;
  local($hr)  = int($min / 60); $min -= $hr  * 60;
  local($day) = int($hr  / 24); $hr  -= $day * 24;
  local($idle) = 'Idle';
  if ($total < 60) {
    $idle .= ($total == 1) ? ' 1 second' : " $total seconds";
  } else {
    $idle .= " $total seconds";
    if ($day > 0) {
      $idle .= sprintf(' (%dd %02d:%02d:%02d)', $day, $hr, $min, $sec);
    } elsif ($hr > 0) {
      $idle .= sprintf(' (%02d:%02d:%02d)', $hr, $min, $sec);
    } elsif  ($min > 0) {
      $idle .= sprintf(' (%02d:%02d)', $min, $sec);
    }
  }
  &sendS("NOTICE $from :\001FINGER $my_name " .
	 "($my_user\@$machine{$my_nick}) $idle\001\n");
}
sub ctcp_time {
  local($sec, $min, $hour, $mday, $mon, $year, $wday, $tmp, $tmp)
      = localtime;
  local(@month) = ('Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
		   'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec');
  local(@wday) = ('Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat');
  $ctime = sprintf("%s %s %2d %02d:%02d:%02d %04d", $wday[$wday],
		   $month[$mon], $mday, $hour, $min, $sec, $year + 1900);
  &sendS("NOTICE $from :\001TIME $ctime\001\n");
}
sub ctcp_echo {
  local($mes) = $_[0];
  &sendS("NOTICE $from :\001ECHO $mes\001\n");
}
sub ctcp_ping {
  local($mes) = $_[0];
  &sendS("NOTICE $from :\001PING $mes\001\n");
}
sub ctcp_dcc {
  local($mes) = $_[0];
  local($dcc, $arg) = split(/ /, $mes, 2);
  if ($dcc eq 'SEND') {
    ($nm, $sv, $pt, $sz) = ($arg =~ /(\S+) (\S+) (\S+) (\S+)/);
    $file = "$dccdir$nm";
    $fr = $from;
    if (-f $file) {
      local($ext) = '0';
      while (-f "$file.$ext") {
	$ext++;
      }
      $file = "$file.$ext";
    }
    &logF("*** DCC SEND request from $fr: $nm ($sz bytes)\n", 'P');
    &sendCchan("NOTICE $my_nick :DCC SEND request from $fr: $nm ($sz bytes)\n");
    return if $get_dcc eq 'off';
    $dcclogfile = sprintf("%s%sdcc", $logdir, $logprefix{'F'})
	unless $dcclogfile;
    if ($dcc_logrec eq 'on') {
      if (open(DCCLOG, ">>$dcclogfile")) {
	chmod($logmode, $dcclogfile);
	&now_time;
	select(DCCLOG); $| = 1; select(F0);
	printf DCCLOG "%04d/%02d/%02d %02d:%02d:%02d[GET ] " .
	    "$nm($sz bytes)\n        from $fr!$machine{$fr}\n",
	    $year, $mon, $mday, $hour, $min, $sec;
	close(DCCLOG);
      }
    }
    unless (fork) {
      unless (fork) {
	if (&dcc_connect) {
	  unless (&dcc_get) {
	    &logF("*** DCC get($nm) from $fr failed.\n", 'P');
	    &sendC("NOTICE $my_nick :DCC get($nm) from $fr failed.\n");
	  }
	}
	$nm = '';
	exit 0;
      }
      exit 0;
    }
    wait;
  }
}

## dcc
sub dcc_listen {
  local($name, $aliases, $prot) = getprotobyname('tcp');
  socket(SV, $PF_INET, $SOCK_STREAM, $prot) || return 0;
  local($host) = ($machine{$my_nick} =~ /\@(.*)$/);
  local(@thisaddr) = gethostbyname($host);
  bind(SV, pack($SOCKADDR, $AF_INET, 0, $thisaddr[4])) || return 0;
  ($tmp, $pt, $addr, $tmp) = unpack($SOCKADDR, getsockname(SV));
  $sv = unpack('N', $addr);
  listen(SV, 1) || return 0;
  select(SV); $| = 1; select(F0);
}
sub dcc_connect {
  local($name, $aliases, $prot) = getprotobyname('tcp');
  local($that) = pack($SOCKADDR, $AF_INET, $pt, pack('N', $sv));
  socket(REMOTE, $PF_INET, $SOCK_STREAM, $prot) || return 0;
  select(REMOTE); $| = 1; select(F0);
  connect(REMOTE, $that) || return 0;
  return 1;
}
sub dcc_get {
  open(FILE, ">$file") || return 0;
  chmod($logmode, $file);
  local($done, $rest, $size) = (0, $sz, 4096);
  local($count, $times, $rate) = (0, time, 0);
  while ($rest > 0) {
    $size = $rest if $size > $rest;
    if ($len = sysread(REMOTE, $tmp, $size)) {
      select(FILE); $| = 1;
      print FILE $tmp;
      $done += $len;
      $rest -= $len;
      local($pc) = int($done / $sz * 100);
      print REMOTE pack('N', $done);
      if (++$count == 16) {
	$count = 0;
	&sendCchan("NOTICE $my_nick :DCC getting $nm from $fr: " .
		   "$pc % ($done/$sz)\n");
      }
    } else {
      return 0;
    }
  }
  close(FILE);
  close(REMOTE);
  &logF("*** DCC get($nm) done.\n", 'P');
  local($sa) = time - $times;
  $rate = sprintf("%.2f", $done / $sa) if $sa > 0;
  &sendCchan("NOTICE $my_nick :DCC get($nm) from $fr done.($rate bytes/sec)\n");
  return 1;
}
sub dcc_send {
  local($who) = $_[0];
  open(FILE, $file) || return 0;
  local($done, $rest, $size) = (0, $sz, 4096);
  local($rin, $rout, $count, $times, $rate);
  vec($rin, fileno(REMOTE), 1) = 1;
  $times = time;
  while ($rest > 0) {
    $size = $rest if $size > $rest;
    if ($len = sysread(FILE, $tmp, $size)) {
      print REMOTE $tmp;
      $done += $len;
      $rest -= $len;
      if (++$count == 16) {
        $count = 0;
        while (sysread(REMOTE, $tmp, 4) > 0 && unpack('N', $tmp) != $done) {
        }
	local($pc) = int ($done / $sz * 100);
	&sendC("NOTICE $my_nick :DCC sending $nm to $who: " .
	       "$pc% ($done/$sz)\n");
      }
    } else {
      return 0;
    }
  }
  while (sysread(REMOTE, $tmp, 4) > 0 && unpack('N', $tmp) != $done) {
  }
  close(FILE);
  close(REMOTE);
  &logF("*** DCC send($nm) to $who done.\n", 'P');
  local($sa) = time - $times;
  $rate = sprintf("%.2f", $done / $sa) if $sa > 0;
  &sendC("NOTICE $my_nick :DCC send($nm) to $who done.($rate bytes/sec)\n");
  return 1;
}

# naruting
sub check_mode_o {
  local($chan, $mode, $nick, $o_count) = split(/ /,shift @naruto);
  return unless $chan;
  local($chanr, $chanv) = &local_chan($chan);
  $o_count-- if $o_count > 0;
  if ($o_count == 0) {
    if (&ExistList($nameslist{$chanv}, "\@$my_nick")) {
      if ($mode eq '+' &&
	  !&ExistList($nameslist{$chanv}, "\@$nick") &&
	  &ExistList($nameslist{$chanv}, $nick)) {
	&sendS("MODE $chanr +o :$nick\n");
      } elsif ($mode eq '-' &&
	       &ExistList($nameslist{$chanv},"\@$nick")) {
	&sendS("MODE $chanr -o :$nick\n");
      }
    }
  } else {
    push (@naruto, "$chanv $mode $nick $o_count");
  }
}
sub check_mode_b {
  local($chan, $where, $b_count) = split(/\s/,shift @rmban);
  return unless $chan;
  local($chanr, $chanv) = &local_chan($chan);
  $b_count-- if $b_count > 0;
  if ($b_count == 0 && $chanv) {
    &sendS("MODE $chanr -b :*!$where\n");
  } else {
    push (@rmban, "$chanv $where $b_count");
  }
}
sub set_mode {
  local($from2) = "$from!$where";
  $from2 =~ s/!~/!/g;
  local($chanv) = $_[0];
  &logF("[d] chanv = $chanv\n", 'D');
  &logF("[d] from  = $from2\n", 'D');
  foreach (@modes) {
    next unless /\S/;
    local($chan, $mode, $list) = (/^(.*)\s*\((\S)\)\s*:\s*(.*)$/);
    next if (!&check_chan($chan) && $chan);
    $chan =~ s/\s//g;
    &logF("[d] chan  = $chan\n", 'D');
    next if ($chan && $chan ne $chanv);
    if ($mode eq 'm') {
      $privmsg{$chanv} = $list;
      next;
    }
    if ($mode eq 'M') {
      $kickpriv{$chanv} = $list;
      next;
    }
    $list =~ s/\./\\\./g;
    $list =~ s/\@/\\\@/g;
    $list =~ s/\?/./g;
    $list =~ s/\*/.*/g;
    &logF("[d] list  = $list\n", 'D');
    foreach $nick (split(/\s+/, $list)) {
      if ($from2 =~ /^$nick$/i) {
	&logF("[d] nick  = $nick\n", 'D');
	if ($mode eq 'p' && $auto_priv ne 'off' && $privmsg{$chanv}) {
	  &sendS("PRIVMSG $from :$privmsg{$chanv}\n");
	  next;
	}
	if ($mode eq 'k' && $auto_kick ne 'off') {
	  if ($kick_priv ne 'off' && $kickpriv{$chanv}) {
	    &sendS("PRIVMSG $from :$kickpriv{$chanv}\n");
	  }
	  local($chanr, $chanv) = &local_chan($chanv);
	  &sendS("MODE $chanr +b :*!$where\n");
	  &sendS("KICK $chanr :$from\n");
	  push (@rmban, "$chanv $where $b_count_def");
	  next;
	}
	local($o_count_time);
	if ($o_count_random) {
	  $o_count_time = int(rand($o_count_def)+1);
	} else {
	  $o_count_time = $o_count_def;
	}
	push (@naruto, "$chanv $mode $from $o_count_time");
	last;
      }
    }
  }
}
sub check_mem {
  local($tmp) = $_[0];
  $tmp =~ s/(\W)/\\$1/g;
  for ( $i = 0 ; $i < $#naruto ; $i++ ) {
    local($chanv, $mode, $nick, $o_count) = split(/ /,shift @naruto);
    if ($nick !~ /^$tmp/i) {
      push (@naruto, "$chanv $mode $nick $o_count");
    }
  }
}

# send server or client
sub sendS {
  return unless $Sconnect;
  local($mes) = $_[0];
  $mes =~ s/\033\$\@/\033\$B/g;
  $mes =~ s/\033\(J/\033\(B/g;
  print SERVER $mes if $mes;
  &logF("[S] $mes", 'D');
}
sub sendC {
  local($mes) = $_[0];
  return unless $C;
  print $C $mes if $mes;
  &logF("[C] $mes", 'D');
}
sub sendCok {
  local($mes) = $_[0];
  for ($CCn = 0; $CCn <= $maxCn; $CCn++) {
    $CC = $C[$CCn];
    print $CC $mes if vec($Cok, $CCn, 1);
  }
  &logF("[Co] $mes", 'D');
}
sub sendCchan {
  local($mes) = $_[0];
  for ($CCn = 0; $CCn <= $maxCn; $CCn++) {
    $CC = $C[$CCn];
    print $CC $mes if vec($Cok, $CCn, 1) && !vec($Cchan, $CCn, 1);
  }
  &logF("[Cc] $mes", 'D');
}
sub sendCchan2 {
  local($mes) = $_[0];
  for ($CCn = 0; $CCn <= $maxCn; $CCn++) {
    $CC = $C[$CCn];
    print $CC $mes if vec($Cok, $CCn, 1) && !vec($Cchan, $CCn, 1) && $Cn != $CCn;
  }
  &logF("[C2] $mes", 'D');
}  

# list
sub InitList {
  $_[0] = "$;";
}
sub AddList {
  unless (&ExistList) {
    $_[0] .= "$_[1]$;";
    return 1;
  }
  return 0;
}
sub DelList {
  local($tmp) = $_[1];
  $tmp =~ s/(\W)/\\$1/g;
  if ($_[0] =~ /$;$tmp$;/i) {
    substr($_[0], index($_[0], "$;$_[1]$;"), length("$;$_[1]$;")) = "$;";
    return 1;
  }
  return 0;
}
sub ExistList {
  local($tmp) = $_[1];
  $tmp =~ s/(\W)/\\$1/g;
  if ($_[0] =~ /$;($tmp)$;/i) {
    substr($_[0], index($_[0], "$;$1$;"), length("$;$1$;")) = "$;";
    $_[0] .= "$_[1]$;";
    return 1;
  }
  return 0;
}
sub ChangeList {
  local($tmp) = $_[1];
  $tmp =~ s/(\W)/\\$1/g;
  if ($_[0] =~ /$;$tmp$;/i) {
    substr($_[0], index($_[0], "$;$_[1]$;"), length("$;$_[1]$;")) = "$;$_[2]$;";
    return 1;
  }
  return 0;
}

# log
sub logF {
  &now_time;
  local($mes, $chan) = @_;
  if ($no_log ne 'all' && !&ExistList($no_log, $chan)) {
    &logwrite($mes, $chan);
    select(F0); $| = 1;
    return if (!$taillog || $chan eq 'D' || $mes =~ /^TAIL: /);
    push(@tail, "TAIL: $header$mes");
    shift(@tail) if $#tail > $taillog;
  }
}
sub logwrite {
  local($mes, $chan) = @_;
  if ($logprefix{$chan} && !$logfile{$chan} &&
      $chan ne 'F' && $chan ne 'P' && $chan ne 'D') {
    &open_log($chan);
    chmod($logmode, $logfile{$chan});
  }
  if ($chan eq 'D') {
    if ($fh{'D'}) {
      select(F2); $| = 1;
      print F2 $header, $mes;
    }
  } elsif ($chan eq 'P' && $fh{'P'}) {
    select(F1); $| = 1;
    print F1 $header, $mes;
  } elsif ($chan eq 'ALL') {
    local($ff) = 0;
    local($fpx);
    &InitList($fpx);
    foreach (keys(%fh)) {
      next if &ExistList($fpx, $logprefix{$_});
      next if (!&ExistList($autojoinchanlist, $_) && $_ ne 'F' &&
	       $_ ne 'P' && $_ ne 'D');
      next unless $logprefix{$_};
      &AddList($fpx, $logprefix{$_});
      local($fh) = $fh{$_};
      local($from2) = $from;
      $from2 =~ s/(\W)/\\$1/g;
      if ($mes =~ /^! $from2/ || $mes =~ /^$from2 -> /) {
	if (&ExistList($nameslist{$_}, $from) ||
	    &ExistList($nameslist{$_}, "\+$from") ||
	    &ExistList($nameslist{$_}, "\@$from")) {
	  select($fh); $| = 1;
	  print $fh $header, $mes;
	} else {
	  $ff = 1;
	}
      } else {
	select($fh); $| = 1;
	print $fh $header, $mes;
      }
    }
    select(F0); $| = 1;
    print F0 $header , $mes if $ff == 1;
    undef($ff);
  } elsif ($fh{$chan} && $logprefix{$chan}) {
    local($fh) = $fh{$chan};
    select($fh); $| = 1;
    print $fh $header, $mes;
  } else {
    select(F0); $| = 1;
    print F0 $header, $mes;
  }
}
sub open_log {
  local($chan) = $_[0];
  local($prefix) = ($logprefix{$chan} =~ /([^\/]*)$/);
  foreach ("$logdir$logprefix{$chan}", "$logdir$prefix", "./$prefix") {
    $logfile{$chan} = sprintf("%s%02d%02d", $_, $mon, $mday);
    local($fh) = $fh{$chan};
    return if open($fh, ">>$logfile{$chan}");
  }
}
sub now_time {
  ($sec, $min, $hour, $mday, $mon, $year) = localtime(time);
  $mon++;
  $year += 1900;
  $header = sprintf("%02d:%02d:%02d ", $hour, $min, $sec);
  $header = sprintf("%02d%02d%02d ", $hour, $min, $sec) if $timefmt == 1;
  $header = sprintf("%02d:%02d ", $hour, $min) if $timefmt == 2;
}
sub day {
  local($fpx);
  &InitList($fpx);
  foreach (keys(%fh)) {
    next if &ExistList($fpx, $logprefix{$_});
    next if (&ExistList($nojoinchanlist, $_) &&
	     !&ExistList($autojoinchanlist, $_));
    next unless $logprefix{$_};
    &AddList($fpx, $logprefix{$_});
    local($fh) = $fh{$_};
    if ($logfile{$_}) {
      printf $fh "%04d/%02d/%02d %02d:%02d:%02d end\n", $year, $mon, $mday, $hour, $min, $sec;
      close($fh);
    }
    if ($log_mail && -f $logfile{$_}) {
      local($mail) = $log_mail;
      local($lfn) = ($logfile{$_} =~ /^$logdir(.*)/);
      $mail =~ s/\$logfile/$lfn/;
      if ($log_mail_to{$_}) {
	foreach $to (split(/$;/, $log_mail_to{$_})) {
	  next unless $to;
	  system("$mail $to < $logfile{$_}");
	}
      } elsif ($log_mail_to) {
	foreach $to (split(/$;/, $log_mail_to)) {
	  next unless $to;
	  system("$mail $to < $logfile{$_}");
	}
      }
    }
    if ($log_gzip && -f $logfile{$_}) {
      system("$log_gzip $logfile{$_}");
    }
    &open_log($_);
    chmod($logmode, $logfile{$_});
    &logF("[d] created $logfile{$_} / $_\n", 'D');
    select(F0); $| = 1;
  }
  if ($daemon) {
    open(STDOUT, ">&F0");
    open(STDERR, ">&F0");
  }
}
sub hour {
  &read_pircmodes;
  local($fpx);
  &InitList($fpx);
  foreach (keys(%fh)) {
    next if &ExistList($fpx, $logprefix{$_});
    next if (&ExistList($nojoinchanlist, $_) &&
	     !&ExistList($autojoinchanlist, $_));
    next unless $logprefix{$_};
    &AddList($fpx, $logprefix{$_});
    local($fh) = $fh{$_};
    if ($_ && $fh{$_}) {
      $logfile{$_} = sprintf("%s%s%02d%02d", $logdir, $logprefix{$_}, $mon, $mday);
      unless (-r $logfile{$_} && -w $logfile{$_}) {
	&open_log($_);
	chmod ($logmode, $logfile{$_});
	&logF("[d] created $logfile{$_} / $_\n", 'D');
      }
      printf $fh "%04d/%02d/%02d %02d:%02d:%02d\n", $year, $mon, $mday, $hour, $min, $sec;
    }
  }
  $down_time-- if $down_time > 0;
  if ($down_time == 0) {
    for ($i = 0; $i < $maxCn; $i++) {
      if (vec($Call, $i, 1) == 1) {
	$down_time++;
	return;
      }
    }
    &logF("down by myself\n", 'ALL');
    &sendS("QUIT :$down_mes\n");
    exit 0;
  }
}
sub taillog {
  if($taillog) {
    foreach (@tail) {
      next unless $_;
      &sendC("NOTICE $my_nick :$_");
    }
    &sendC("NOTICE $my_nick :end pirc taillog $taillog lines\n");
  }
}

# check
sub check_names {
  local($chan) = $_[0];
  return if $auto_get eq 'off';
  return if ($nameslist{$chan} ne "$;$my_nick$;" &&
	     $nameslist{$chan} ne "$;\+$my_nick$;");
  local($chanr, $chanv) = &local_chan($chan);
  &sendS("PART :$chanr\n");
  if (&check_chan($chanv)) {
    &sendS("JOIN $chanr :$autokey{$chanv}\n");
    &sendS("MODE $chanr $automode{$chanv} \n");
  }
}
sub local_chan {
  local($chan) = local($chanr) = local($chanv) = $_[0];
  if ($chan =~ /^\#.*:\*\.jp/i) { # real to virtual
    $chan =~ s/^\#/%/;
    $chan =~ s/:\*\.jp$//i;
    $chanv = $chan;
  }
  if ($chan =~ /^%/) {		# virtual to real
    $chan =~ s/^%/\#/;
    $chan .= ':*.jp';
    $chanr = $chan;
  }
  return($chanr, $chanv);
}
sub check_chan {
  $_[0] =~ s/\033\$\@/\033\$B/g;
  $_[0] =~ s/\033\(J/\033\(B/g;
  foreach (split(/,[\#%&]/, $_[0])) {
    if ($_ =~ /\033\$B.*,.*\033\(B/) {
      return 0;
    } else {
      return 1;
    }
  }
}

# other...
sub down {
  print STDERR $_[0];
  kill('TERM', $mpidp);
  exit 0;
}
sub mynames {
  foreach $chan (split(/$;/, $chanlist)) {
    next unless $chan;
    next unless $nameslist{$chan};
    local($chanr, $chanv) = &local_chan($chan);
    local($len) = local($len0) = length(":PIRC 353 $my_nick = $chanr :");
    local($tmp) = '';
    foreach $name (split(/$;/, $nameslist{$chanv})) {
      next unless $name;
      if ($len + length($name) + 1 > 510) {
	&sendC(":PIRC 353 $my_nick = $chanr :$tmp\n");
	$len = $len0;
	$tmp = '';
      }
      $len += length($name) + 1;
      $tmp .= $name . ' ';
    }
    if ($tmp) {
      &sendC(":PIRC 353 $my_nick = $chanr :$tmp\n");
    }
    &sendC(":PIRC 366 $my_nick $chanr :* End of /NAMES list.\n");
  }
}
sub mynames2 {
  foreach $chan (split(/$;/, $chanlist)) {
    next unless $chan;
    local($chanr, $chanv) = &local_chan($chan);
    &sendC(":$my_nick!$machine{$my_nick} JOIN :$chanr\n");
    if ($topics{$chanv}) {
      &sendC(":PIRC 332 $my_nick $chanr :$topics{$chanv}\n");
    }
    local($len) = local($len0) = length(":PIRC 353 $my_nick = $chanr :");
    local($tmp) = '';
    foreach $name (split(/$;/, $nameslist{$chanv})) {
      next unless $name;
      if ($len + length($name) + 1 > 510) {
	&sendC(":PIRC 353 $my_nick = $chanr :$tmp\n");
	$len = $len0;
	$tmp = '';
      }
      $len += length($name) + 1;
      $tmp .= "$name ";
    }
    &sendC(":PIRC 353 $my_nick = $chanr :$tmp\n") if $tmp;
    &sendC(":PIRC 366 $my_nick $chanr :* End of /NAMES list.\n");
  }
}
sub chanall {
  foreach $chan (split(/$;/, $chanlist)) {
    next unless $chan;
    $Cchan{$chan} = $Cchan{$chan};
    vec($Cchan{$chan}, $Cn, 1) = 0;
  }
}
sub mychan {
  &sendC("NOTICE $my_nick :You are in");
  foreach $chan (split(/$;/, $chanlist)) {
    next unless $chan;
    if (vec($Cchan{$chan}, $Cn, 1)) {
      &sendC(" ($chan)");
    } else {
      &sendC(" $chan");
    }
  }
  &sendC(".\n");
}
sub autojoins {
  if ($autojoinchanlist eq "$;") {
    &sendC("NOTICE $my_nick :no autojoins\n");
  } else {
    local($tmp) = '';
    foreach $chan (split(/$;/, $autojoinchanlist)) {
      next unless $chan;
      $tmp .= " $chan";
    }
    &sendC("NOTICE $my_nick :autojoin:$tmp\n");
  }
}
sub automodes {
  if ($automodechanlist eq "$;") {
    &sendC("NOTICE $my_nick :no automodes\n");
  } else {
    local($tmp) = '';
    foreach $chan (split(/$;/, $automodechanlist)) {
      next unless $chan;
      $tmp .= " $chan($automode{$chan})";
    }
    &sendC("NOTICE $my_nick :automode:$tmp\n");
  }
}
sub autokeys {
  if ($autokeychanlist eq "$;") {
    &sendC("NOTICE $my_nick :no autokeys\n");
  } else {
    local($tmp) = '';
    foreach $chan (split(/$;/, $autokeychanlist)) {
      next unless $chan;
      $tmp .= " $chan\[$autokey{$chan}\]";
    }
    &sendC("NOTICE $my_nick :autokey:$tmp\n");
  }
}
sub make_list {
  if (&ExistList($chanlist, $chanv)) {
    $list =~ s/ /$;/g;
    if ($lastnameschannel eq $chanv) {
      $nameslist{$chanv} .= "$list";
    } else {
      $nameslist{$chanv} = "$;$list";
    }
  }
  $lastnameschannel = $chanv;
}

## end of madoka-chan
