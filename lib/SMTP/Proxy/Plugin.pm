package SMTP::Proxy::Plugin;

use strict;
use warnings;

use vars qw($ATTACH);

sub attach_to {
   my ($class, $stage, $code) = @_;
   if( ! exists $ATTACH->{$stage}) {
      $ATTACH->{$stage} = [];
   }

   push @{$ATTACH->{$stage}}, $code;
}

sub get_code_for {
   my ($class, $stage) = @_;
   return $ATTACH->{$stage} if exists $ATTACH->{$stage};
   return [];
}

1;
