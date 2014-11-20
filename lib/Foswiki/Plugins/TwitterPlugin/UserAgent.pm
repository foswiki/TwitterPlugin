# Plugin for Foswiki - The Free and Open Source Wiki, http://foswiki.org/
#
# TwitterPlugin is Copyright (C) 2014 Michael Daum http://michaeldaumconsulting.com
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details, published at
# http://www.gnu.org/copyleft/gpl.html

package Foswiki::Plugins::TwitterPlugin::UserAgent;

use strict;
use warnings;

use Foswiki::Func();
use LWP::UserAgent();
use Cache::FileCache ();
our @ISA = qw( LWP::UserAgent );

sub new {
  my $class = shift;

  my $this = $class->SUPER::new(@_);

  $this->{cacheExpire} = $Foswiki::cfg{TwitterPlugin}{CacheExpire};
  $this->{cacheExpire} = 3600 unless defined $this->{cacheExpire}; 

  $this->{cache} = Cache::FileCache->new({
      'cache_root' => Foswiki::Func::getWorkArea('TwitterPlugin') . '/cache',
      'default_expires_in' => $this->{cacheExpire},
      'directory_umask' => 077,
    }
  );

  return $this;
}

sub expires {
  my ($this, $val) = @_;

  if (defined $val) {
    my $oldVal = $this->{cacheExpire};
    $this->{cacheExpire} = $val;
    return $oldVal;
  }

  return $this->{cacheExpire};
}

sub request {
  my $this = shift;
  my @args = @_;
  my $request = $args[0];

  return $this->SUPER::request(@args) if $request->method ne 'GET';

  my $cgiObj = Foswiki::Func::getRequestObject();
  my $refresh = $cgiObj->param("refresh") || '';
  $refresh = ($refresh =~ /^(on|twitter)$/) ? 1:0;

  my $uri = $request->uri->as_string;
  my $obj;

  #print STDERR "uri=$uri\n";

  $obj = $this->{cache}->get($uri) unless $refresh;

  if (defined $obj) {
    #print STDERR "... found in cache $uri\n";
    return HTTP::Response->parse($obj);
  } else {
    #print STDERR " ... fetching $uri\n";
  }

  my $res = $this->SUPER::request(@args);

  ## cache only "200 OK" content
  if ($res->code eq HTTP::Status::RC_OK) {
    $this->{cache}->set($uri, $res->as_string, $this->{cacheExpire});
  }

  return $res;
}

1;
