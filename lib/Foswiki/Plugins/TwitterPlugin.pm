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

package Foswiki::Plugins::TwitterPlugin;

use strict;
use warnings;

use Foswiki::Func ();

our $VERSION = '3.10';
our $RELEASE = '24 Oct 2017';
our $SHORTDESCRIPTION = 'Access Twitter via Foswiki';
our $NO_PREFS_IN_TOPIC = 1;
our $core;

sub initPlugin {

  Foswiki::Func::registerTagHandler('TWITTER', sub { return getCore()->TWITTER(@_); });

  Foswiki::Func::registerRESTHandler(
    'update',
    sub {
      return getCore()->restUpdate(@_);
    },
    authenticate => 1,
    validate => 1,
    http_allow => 'POST',
    description => 'Send a status update to a twitter account.'
  );

  Foswiki::Func::registerRESTHandler('purgeCache', sub { return getCore()->purgeCache(@_); },
    authenticate => 1,
    validate => 0,
    http_allow => 'GET,POST',
  );

  Foswiki::Func::registerRESTHandler('clearCache', sub { return getCore()->clearCache(@_); },
    authenticate => 1,
    validate => 0,
    http_allow => 'GET,POST',
  );

  return 1;
}

sub getCore {
  unless (defined $core) {
    require Foswiki::Plugins::TwitterPlugin::Core;
    $core = Foswiki::Plugins::TwitterPlugin::Core->new();
  }
  return $core;
}



sub finishPlugin {
  undef $core;
}

1;
