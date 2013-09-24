package RSS::From::Twitter;

use 5.010001;
use strict;
use warnings;
use Log::Any qw($log);

use HTML::Entities;
use LWP::UserAgent;
use Mojo::DOM;
use Perinci::Sub::Util qw(err);
use POSIX;
use URI::Escape;

require Exporter;
our @ISA       = qw(Exporter);
our @EXPORT_OK = qw(
                       get_rss_from_twitter
                       get_rss_from_twitter_list
                       get_rss_from_twitter_search
                       get_rss_from_twitter_user
               );

# VERSION

our %SPEC;

my %common_args = (
    ua => {
        summary     => 'Supply a custom LWP::UserAgent object',
        schema      => 'obj',
        description => <<'_',

If supplied, will be used instead of the default LWP::UserAgent object.

_
    },
);

$SPEC{get_rss_from_twitter} = {
    v => 1.1,
    summary => 'Convert Twitter page to RSS',
    description => <<'_',

In June 2013, Twitter retired the RSS v1 API (e.g.
http://search.twitter.com/search.rss?q=blah, etc). However, its replacement, the
v1.1 API, is not as straightforward to use (e.g. needs auth). This function
scrapes the Twitter search result page (e.g. https://twitter.com/search?q=blah)
and converts it to RSS. I wrote this because I have other scripts expecting RSS
input.

Expect breakage from time to time though, as scraping method is rather fragile.

_
    args    => {
        %common_args,
        url => {
            summary  => 'URL, e.g. https://twitter.com/foo or file:/test.html',
            schema   => 'str*',
            pos      => 0,
            req      => 1,
        },
        title => {
            summary  => 'RSS title',
            schema   => 'str*',
        },
    },
};
sub get_rss_from_twitter {
    my %args = @_;

    my $datefmt = "%a, %d %b %Y %H:%M:%S %z";
    state $default_ua = LWP::UserAgent->new;

    my $url   = $args{url} or return err(400, "Please specify url");
    my $ua    = $args{ua} // $default_ua;
    my $title = $args{title} // "Twitter page";

    my $uares;
    eval { $uares = $ua->get($url) };
    return err(500, "Can't download URL `$url`: $@") if $@;
    return err($uares->code, "Can't download URL: " . $uares->message)
        unless $uares->is_success;

    my $dom;
    eval { $dom = Mojo::DOM->new($uares->content) };
    return err(500, "Can't create DOM from read URL: $@") if $@;

    my $gen = "RSS::From::Twitter " .
        ($RSS::From::Twitter::Search::VERSION // "?"). " (Perl module)";

    my @rss;

    push @rss, '<?xml version="1.0" encoding="UTF-8">',"\n";
    push @rss, "<!-- generator=$gen -->\n";
    push @rss, ('<rss version="2.0"',
                ' xmlns:content="http://purl.org/rss/1.0/modules/content/"',
                ' xmlns:wfw="http://wellformedweb.org/CommentAPI/"',
                ' xmlns:dc="http://purl.org/dc/elements/1.1/"',
                ' xmlns:atom="http://www.w3.org/2005/Atom"',
                ' xmlns:sy="http://purl.org/rss/1.0/modules/syndication/"',
                ' xmlns:slash="http://purl.org/rss/1.0/modules/slash/"',
                ">\n");
    push @rss, "<channel>\n";
    push @rss, "<title>",encode_entities($title),"</title>\n";
    push @rss, "<link>$url</link>\n";
    push @rss, "<generator>$gen</generator>\n";
    push @rss, "<lastBuildDate>",
        POSIX::strftime($datefmt, gmtime),
              "</lastBuildDate>\n";
    push @rss, "\n";

    my $tweets = $dom->find("div.tweet");
    for my $tweet (@$tweets) {
        my $html = "$tweet";
        my ($url) = $html =~ m!(/[^/]+/status/\d+)!;
        my $fullname = $tweet->find(".fullname")->text;
        my ($username) = $tweet->find(".username") =~ m!<b>(.+)</b>!;
        my $text = $tweet->find(".tweet-text"); $text = "$text"; $text =~ s!<.+?>!!sg;
        my ($time) = $tweet->find(".tweet-timestamp") =~ /data-time="(\d+)"/;

        push @rss, "<item>\n";
        push @rss, "<title>$fullname (\@$username)</title>\n";
        push @rss, "<link>https://twitter.com$url</link>\n";
        push @rss, "<pubDate>",
            strftime($datefmt, gmtime($time)),
                "</pubDate>\n";
        push @rss, "<description>$text</description>\n";
        push @rss, "</item>\n\n";
    }

    push @rss, "</channel>\n";
    push @rss, "</rss>\n";

    [200, "OK", join("", @rss)];
}

$SPEC{get_rss_from_twitter_list} = {
    v => 1.1,
    summary => 'Convert Twitter public list page to RSS',
    description => <<'_',

This function calls get_rss_from_twitter() with URL:
`https//twitter.com/USERNAME/LISTNAME`.

_
    args    => {
        %common_args,
        username => {
            summary  => 'Twitter username',
            schema   => 'str*',
            pos      => 0,
            req      => 1,
        },
        listname => {
            summary  => "User's list name",
            schema   => 'str*',
            pos      => 1,
            req      => 1,
        },
    },
};
sub get_rss_from_twitter_list {
    my %args = @_;

    # XXX schema
    my $username = delete($args{username})
        or return err(400, "Please specify username");
    my $listname = delete($args{listname})
        or return err(400, "Please specify listname");

    my $url = "https://twitter.com/".uri_escape($username).
        "/".uri_escape($listname);
    get_rss_from_twitter(
        %args,
        url=>$url,
        title=>"Twitter public list page: $username/$listname",
    );
}

$SPEC{get_rss_from_twitter_search} = {
    v => 1.1,
    summary => 'Convert Twitter search result page to RSS',
    description => <<'_',

This function calls get_rss_from_twitter() with URL:
`https//twitter.com/search?q=QUERY`.

_
    args    => {
        %common_args,
        query => {
            summary  => 'Search query',
            schema   => 'str*',
            pos      => 0,
            req      => 1,
        },
    },
};
sub get_rss_from_twitter_search {
    my %args = @_;

    # XXX schema
    my $query = delete($args{query})
        or return err(400, "Please specify query");

    my $url = "https://twitter.com/search?q=".uri_escape($query);
    get_rss_from_twitter(
        %args,
        url=>$url,
        title=>"Twitter search page: $query",
    );
}

$SPEC{get_rss_from_twitter_user} = {
    v => 1.1,
    summary => 'Convert Twitter user main page to RSS',
    description => <<'_',

This function calls get_rss_from_twitter() with URL:
`https//twitter.com/USERNAME`.

_
    args    => {
        %common_args,
        username => {
            summary  => 'Twitter username',
            schema   => 'str*',
            pos      => 0,
            req      => 1,
        },
    },
};
sub get_rss_from_twitter_user {
    my %args = @_;

    # XXX schema
    my $username = delete($args{username})
        or return err(400, "Please specify username");

    my $url = "https://twitter.com/".uri_escape($username);
    get_rss_from_twitter(
        %args,
        url=>$url,
        title=>"Twitter user main page: $username",
    );
}

1;
#ABSTRACT: Convert Twitter page to RSS

=head1 SYNOPSIS

 # Use command-line scripts get-rss-from-twitter{,-list,-search,-user}


=cut
