# Plugin for Foswiki - The Free and Open Source Wiki, http://foswiki.org/
#
# TwitterPlugin is Copyright (C) 2014-2017 Michael Daum http://michaeldaumconsulting.com
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
use Cache::FileCache ();
use LWP::UserAgent();
our @ISA = qw( LWP::UserAgent );

sub new {
  my $class = shift;

  my $this = $class->SUPER::new(@_);

  my $proxy = $Foswiki::cfg{PROXY}{HOST};
  if ($proxy) {
    $this->proxy(['http', 'https'], $proxy);

    my $noProxy = $Foswiki::cfg{PROXY}{NoProxy};
    if ($noProxy) {
      my @noProxy = split(/\s*,\s*/, $noProxy);
      $this->no_proxy(@noProxy);
    }
  }

  $this->{cacheExpire} = $Foswiki::cfg{TwitterPlugin}{CacheExpire};
  $this->{cacheExpire} = 3600 unless defined $this->{cacheExpire}; 

  return $this;
}

sub cache {
  my $this = shift;

  unless ($this->{cache}) {
    $this->{cache} = Cache::FileCache->new({
        'cache_root' => Foswiki::Func::getWorkArea('TwitterPlugin') . '/cache',
        'default_expires_in' => $this->{cacheExpire},
        'directory_umask' => 077,
      }
    );
  }

  return $this->{cache};
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

  my $cacheKey = $Foswiki::cfg{TwitterPlugin}{APIKey} . $uri;

  $obj = $this->cache->get($cacheKey) unless $refresh;

  if (defined $obj) {
    #print STDERR "... found in cache $uri\n";
    return HTTP::Response->parse($obj);
  } else {
    #print STDERR " ... fetching $uri\n";
  }

  my $res = $this->SUPER::request(@args);

  ## cache only "200 OK" content
  if ($res->code eq HTTP::Status::RC_OK) {
    $this->cache->set($cacheKey, $res->as_string, $this->{cacheExpire});
  }

  return $res;
}

1;
