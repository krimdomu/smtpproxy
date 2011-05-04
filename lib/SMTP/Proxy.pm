package SMTP::Proxy;

use strict;
use warnings;

use Net::Server::PreFork;
use base qw(Net::Server::PreFork);

use Socket qw(IPPROTO_TCP TCP_NODELAY);
use IO::Socket qw(:crlf);
use IO::Socket::INET;

use SMTP::Proxy::Plugin;

use constant READ_LEN     => 64 * 1024;
use constant READ_TIMEOUT => 3;
use constant WRITE_LEN    => 64 * 1024;

sub new {
   my $that = shift;
   my $proto = ref($that) || $that;
   my $self = $proto->SUPER::new(@_);

   $self->{'config'} = { @_ };

   bless($self, $proto);

   return $self;
}

sub run {
   my $self = shift;


   $self->SUPER::run(
      port                 => $self->{'config'}->{'port'}               || 25,
      host                 => $self->{'config'}->{'host'}               || '',
      min_servers          => $self->{'config'}->{'min_servers'}        || 5,
      min_spare_servers    => $self->{'config'}->{'min_spare_servers'}  || 5,
      max_spare_servers    => $self->{'config'}->{'max_spare_servers'}  || 10,
      max_servers          => $self->{'config'}->{'max_servers'}        || 20,
      listen               => $self->{'config'}->{'backlog'}            || 1024,

      no_client_stdout     => 1,
      proto                => 'tcp',
      serialize            => 'flock',
   );

}

sub process_request {
   my $self = shift;
   my $c = $self->{'server'}->{'client'};
   setsockopt($c, IPPROTO_TCP, TCP_NODELAY, 1) or die($!);

   my %env = (
      REMOTE_ADDR => $self->{'server'}->{'peeraddr'},
      REMOTE_HOST => $self->{'server'}->{'peerhost'} || $self->{'server'}->{'peeraddr'},
      SERVER_NAME => $self->{'server'}->{'sockaddr'},
      SERVER_PORT => $self->{'server'}->{'sockport'},
   );

   for my $code (@{SMTP::Proxy::Plugin->get_code_for('connect')}) {
      my $c_ret = &$code($c, \%env);
      if($c_ret == -1) { return; }
   }

   REQUEST: {
      $self->connect_proxy();
      my $p = $self->{"proxy_to"};
      my $is_data = 0;
      while(my $line = <$c>) {

         if($line =~ m/^\./mi) {
            $is_data = 0;
         }

         print ">> $line";
         print $p $line;

         if( ! $is_data ) {
            my $proxy_req = $self->read($p);

            print "<< $proxy_req";
            print $c $proxy_req;
         }

         if($line =~ m/^DATA/mi) {
            $is_data = 1;
         }

      }
   }

}

sub child_init_hook {
   my ($self) = @_;

   $self->connect_proxy;
}

sub connect_proxy {
   my ($self) = @_;

   my $c;
   if(! $self->{"proxy_to"}) {
      print "Creating connection to endpoint... ";
      $c = $self->{"proxy_to"} = IO::Socket::INET->new(PeerAddr => $self->{"config"}->{"endpoint"},
                                    PeerPort => $self->{"config"}->{"endpoint_port"} || 25,
                                    Proto    => 'tcp');

      die ("no connection to endpoint...") unless $self->{"proxy_to"};

      my $line = <$c>;

      $self->write($c, "HELO proxy\n");
      my $line = <$c>;

      print " ok\n";
   }
   else {

      $c = $self->{"proxy_to"};
      $self->write($c, "NOOP\n");
      my $line = <$c>;
      if(!$line) {
         $self->{"proxy_to"} = undef;
         return $self->connect_proxy;
      }

      chomp $line;

      print "GOT $line\n";

   }
}

sub write {
   my ($self, $c, $msg) = @_;

   my $len = length($msg);
   for(my $i = 0; $i < $len; $i+=WRITE_LEN) {
      syswrite $c, substr($msg, $i, WRITE_LEN);
   }
}

sub read {
   my ($self, $c) = @_;

   my $buf = "";
   while(my $line = <$c>) {
      if($line =~ m/^\d+-/m) {
         $buf .= $line;
         next;
      }

      if($line =~ m/^\d+/m) {
         $buf .= $line;
         last;
      }
      
   }

   return $buf;
}

1;
