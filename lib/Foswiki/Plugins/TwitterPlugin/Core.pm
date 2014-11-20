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

package Foswiki::Plugins::TwitterPlugin::Core;

use strict;
use warnings;

use Foswiki::Func ();
use Foswiki::Time ();
use Encode ();
use Error qw(:try);
use Net::Twitter ();
use Data::Dump qw(dump);

use constant TRACE => 0;    # toggle me

sub writeDebug {
  return unless TRACE;
  Foswiki::Func::writeDebug("TwitterPlugin::Core - $_[0]");
}

sub urlDecode {
  my $text = shift;

  $text =~ s/%([\da-f]{2})/chr(hex($1))/gei;

  return $text;
}

sub new {
  my $class = shift;

  my $this = bless({
      apiKey => $Foswiki::cfg{TwitterPlugin}{APIKey},
      apiSecret => $Foswiki::cfg{TwitterPlugin}{APISecret},
      accessToken => $Foswiki::cfg{TwitterPlugin}{AccessToken},
      accessSecret => $Foswiki::cfg{TwitterPlugin}{AccessSecret},
      ssl => 1,
      @_
    },
    $class
  );

  return $this;
}

sub agent {
  my $this = shift;

  unless ($this->{agent}) {
    $this->{agent} = Net::Twitter->new(
      useragent_class => 'Foswiki::Plugins::TwitterPlugin::UserAgent',
      ssl => 1,
      traits => [
        'API::RESTv1_1', 
        'InflateObjects', 
      ],
      consumer_key => $this->{apiKey},
      consumer_secret => $this->{apiSecret},
      access_token => $this->{accessToken},
      access_token_secret => $this->{accessSecret},
    );
  }

  return $this->{agent};
}

sub restUpdate {
  my ($this, $session, $plugin, $verb, $response) = @_;

  writeDebug("called restUpdate");

  my $request = $session->{request};
  my $status = $request->param("status");

  writeDebug("status=$status");

  $status = Encode::decode_utf8($status); 

  my $error = 0;
  my $result;
  try {
    $result = $this->agent->update($status);
  } otherwise {
    $error = 1;
    $result = shift;
    $result = _inlineError($result);
  };

  unless ($error) {
    my $url = Foswiki::Func::getViewUrl($session->{webName}, $session->{topicName});
    Foswiki::Func::redirectCgiQuery(undef, $url);
    $result = "OK";
  }

  return $result;
}

sub TWITTER {
  my ($this, $session, $params, $topic, $web) = @_;

  writeDebug("called TWITTER()");

  my $action = $params->{_DEFAULT};
  return _inlineError("no action specified") unless defined $action;

  my $method = "handle_".$action;

  my $result = '';
  writeDebug("calling method $method");
  if ($this->can($method)) {
    try {
      $result = $this->$method($params);
    } otherwise {
      $result = shift;
      $result = _inlineError($result);
    };
  } else {
    return _inlineError("unknown action '$action'");
  }

  Foswiki::Func::addToZone("head", "TWITTERPLUGIN", <<HERE);
<link rel='stylesheet' href='%PUBURLPATH%/%SYSTEMWEB%/TwitterPlugin/twitter.css' media='all' />
HERE

  return $result;
}


sub handle_favorites {
  my ($this, $params) = @_;

  my $oldExpires;
  if (defined $params->{expires}) {
    $oldExpires = $this->ua->expires($params->{expires});
  }

  my $favs = $this->agent->favorites(_params2args($params));

  $this->ua->expires($oldExpires) if defined $oldExpires;

  return $this->renderTimeline($favs, $params);
}

sub handle_get_lists {
  my ($this, $params) = @_;

  my $lists = $this->agent->get_lists(_params2args($params));

  return "<pre>".dump($lists)."</pre>" if Foswiki::Func::isTrue($params->{raw});

  return "" unless $lists;

  my $format = $params->{format};
  my $header = $params->{header} || '';
  my $footer = $params->{footer} || '';
  my $sep = $params->{separator}; 

  $format = '$slug' unless defined $format;
  $sep = ', ' unless $sep;

  my @result = ();
  foreach my $list (@$lists) {
    my $line = $format;

    foreach my $key (qw(id slug name mode subscriber_count member_count full_name description)) {
      $line =~ s/\$$key/$list->{$key}/g;
    }
    push @result, $line;
  }

  return "" unless @result;

  return Foswiki::Func::decodeFormatTokens($header.join($sep, @result).$footer);
}

sub handle_list_statuses {
  my ($this, $params) = @_;

  my $timeline = $this->agent->list_statuses(_params2args($params));

  return $this->renderTimeline($timeline, $params);
}

sub handle_user_timeline {
  my ($this, $params) = @_;

  my $timeline = $this->agent->user_timeline(_params2args($params));

  return $this->renderTimeline($timeline, $params);
}

sub handle_home_timeline {
  my ($this, $params) = @_;

  my $timeline = $this->agent->home_timeline(_params2args($params));

  return $this->renderTimeline($timeline, $params);
}

sub handle_mentions_timeline {
  my ($this, $params) = @_;

  my $timeline = $this->agent->mentions_timeline(_params2args($params));

  return $this->renderTimeline($timeline, $params);
}

sub handle_search {
  my ($this, $params) = @_;

  my $result = $this->agent->search(_params2args($params));

  return $this->renderTimeline($result->statuses, $params);
}

sub renderTimeline {
  my ($this, $timeline, $params) = @_;

  return "<pre>".dump($timeline)."</pre>" if Foswiki::Func::isTrue($params->{raw});

  my $format = $params->{format};
  my $header = $params->{header};
  my $footer = $params->{footer};
  my $sep = $params->{separator} || '';
  my $avatarFormat = $params->{avatar_format};
  my $timeFormat = $params->{time_format};
  my $retweetFormat = $params->{retweet_format};
  my $photoFormat = $params->{photo_format};

  Foswiki::Func::loadTemplate("twitterplugin");  

  $header = $this->_getTemplate("header") unless defined $header;
  $footer = $this->_getTemplate("footer") unless defined $footer;
  $format = $this->_getTemplate("format") unless defined $format;
  $avatarFormat = $this->_getTemplate("avatar") unless defined $avatarFormat;
  $retweetFormat = $this->_getTemplate("retweet") unless defined $retweetFormat;
  $timeFormat = $this->_getTemplate("time") unless defined $timeFormat;
  $photoFormat = $this->_getTemplate("photo") unless defined $photoFormat;

  my $statusUrl = "https://twitter.com/\$screen_name/status/\$id";
  my $profileUrl = "https://twitter.com/\$screen_name";
  
  my @results = ();
  foreach my $item (@$timeline) {
    my $line = $format;

    my $user = $item->user;
    my $text = $item->{text};
    my $retweet = '';
    my $origUser;

    if ($item->{retweeted_status}) {
      $origUser = $item->retweeted_status->user;
      $retweet = $retweetFormat;
      $text = $item->retweeted_status->text;
    }

    my $media = '';
    if ($item->entities->{media}) {
      my @media = ();
      foreach my $media (@{$item->entities->media}) {
        next unless $media->type eq 'photo';
        my $mediaLine = $photoFormat;
        $mediaLine =~ s/\$url/$media->media_url_https/ge;
        $mediaLine =~ s/\$width/$media->sizes->small->w/ge;
        $mediaLine =~ s/\$height/$media->sizes->small->h/ge;
        $mediaLine =~ s/\$display_url/$media->expanded_url/ge;
        push @media, $mediaLine;
      }
      $media = "<div class='media'>".join("\n", @media)."</div>" if @media;
    }

    $text =~ s#(https?://[^\s<>]+)#<a href='$1'>$1</a>#g;
    $text =~ s#\@([a-z0-9]+)#<a href='https://twitter.com/$1'>\@$1</a>#g;
    $text = '<literal>'.$text.'</literal>';

    $line =~ s/\$avatar/$avatarFormat/g;
    $line =~ s/\$time/$timeFormat/g;
    $line =~ s/\$url/$statusUrl/g;
    $line =~ s/\$profile_url/$profileUrl/g;
    $line =~ s/\$retweet/$retweet/g;
    $line =~ s/\$media/$media/g;

    $line =~ s/\$profile_url/$user->url/ge;
    $line =~ s/\$profile_image_url/$user->profile_image_url_https/ge;

    $line =~ s/\$text/$text/g;
    $line =~ s/\$created_at/$item->created_at/ge;
    $line =~ s/\$relative_created_at/$item->relative_created_at/ge;
    $line =~ s/\$screen_name/$user->screen_name/ge;
    $line =~ s/\$name/$user->name/ge;
    $line =~ s/\$orig_screen_name/$origUser->screen_name/ge;
    $line =~ s/\$orig_name/$origUser->name/ge;
    $line =~ s/\$id/$item->{id}/g;

    $line = Encode::encode($Foswiki::cfg{Site}{CharSet}, $line); 
    push @results, $line;
  }
  return '' unless @results;

  return Foswiki::Func::decodeFormatTokens($header.join($sep, @results).$footer);
}

sub _getTemplate {
  my ($this, $name) = @_;

  return '' unless $name;
  $name = 'twitter::' . $name;

  unless (defined $this->{$name}) {
    unless (defined $this->{twitterplugin}) {
      $this->{twitterplugin} = Foswiki::Func::loadTemplate("twitterplugin");
    }
    $this->{$name} = Foswiki::Func::expandTemplate($name) || '';
  }

  return $this->{$name};
}

sub _params2args {
  my $params = shift;

  my %args = %$params;
  delete $args{_DEFAULT};
  delete $args{_RAW};
  delete $args{format};
  delete $args{header};
  delete $args{footer};
  delete $args{separator};
  delete $args{expires};

  foreach my $key (keys %args) {
    delete $args{$key} if $key =~ /_format$/;
  }

  return \%args;
}

sub _inlineError {
  my $msg = shift;

  $msg =~ s/ at .*$//g;# unless Foswiki::Func::isAnAdmin();
  return "<span class='foswikiAlert'>".$msg.'</span>';
}


1;