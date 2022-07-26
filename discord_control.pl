# Openkore to Discord
# Author: nikkoxgonzales
# Version: 1
# Language: perl
# Date: April 28, 2022
# Credits: sctnightcore

# Make sure you have the following in your config.txt:
# discord_status 1
# discord_update 1
# discord_delay 2
# discord_update_delay 5
# discord_token 
# discord_channel_id
# discord_webhook
# Otherwise, this will not work.


package discordControl;

# use warnings;
use strict;
use Plugins;
use Globals;
use Log qw(message warning error debug);
use Misc;
use Network;
use Utils;

use LWP::UserAgent ();
use JSON::Tiny qw(decode_json encode_json);
use Data::Dumper;
use Commands;

Plugins::register('discordControl', 'Control openkore using discord.', \&onUnload, \&onReload);

my $log_hook = Log::addHook(\&logDiscord,'');
my $hooks = Plugins::addHooks(
   ['start3', \&onStart3, undef],
   ['AI_post', \&main, undef]
);

sub onUnload {
   Plugins::delHooks($hooks);
   Log::delHook($log_hook);
}

sub onReload {
	onUnload();
}

sub onStart3 {
    my (undef, $args) = @_;
    message("\n\nOpenkore to discord integration on!\n\n", 'openkore-discord');
}

our $ua = LWP::UserAgent->new(timeout => 1);
our $baseUrl = "https://www.discordapp.com/api/";
our $timeDiscord = time;
our $timeDiscordUpdate = time;
our $lastMsgUser;
our $lastMsg;
our $lastMsgID;

sub main {
    my (undef, $args) = @_;
    return if (!$config{discord_status} || !$config{discord_webhook} || !$config{discord_channel_id}) || !$config{discord_token};

    my $delay = $config{discord_delay} || 2;
    if (timeOut($timeDiscord, $delay)) {
        discordGetMessage($config{discord_token}, $config{discord_channel_id});
        $timeDiscord = time;
    }

    my $delayUpdate = $config{discord_update_delay} || 5;
    if ($config{discord_update} && timeOut($timeDiscordUpdate, $delayUpdate)) {
        discordPostMessage(charInfo());
        $timeDiscordUpdate = time;
    }
}

sub logDiscord {
	my ($type, $domain, $level, $globalVerbosity, $message, $user_data) = @_;
    return if (!$config{discord_status} || !$config{discord_webhook} || !$config{discord_channel_id}) || !$config{discord_token};
    return if ($domain eq 'openkore-discord' || !$user_data);
    my (@message) = split(/\n/,$message);
    foreach $message (@message) {
        discordPostMessage("`$message`");
    }
}

sub charInfo {
    my $ai = AI::action if AI::action;
    my $name = $char->{name};
    my $x = $char->{pos_to}{x};
    my $y = $char->{pos_to}{y};
    my $map = $field->baseName;
    my $bLv = $char->{lv};
    my $jLv = $char->{lv_job};
    my $class = $jobs_lut{$char->{jobID}};
    my $bExp = sprintf("%.1f", $char->{exp} / $char->{exp_max} * 100);
    my $jExp = sprintf("%.1f", $char->{exp_job} / $char->{exp_job_max} * 100);
    my $hp = sprintf("%.0f", $char->{hp} / $char->{hp_max} * 100);
    my $sp = sprintf("%.0f", $char->{sp} / $char->{sp_max} * 100);
    my $party = $char->{party}{name};
    my $partyCount = scalar @partyUsersID;
    my $partyExpShare = ($char->{party}{share} ? "Even Shared" : "Each Take");
    my $guild = $char->{guild}{name};
    my $timestamp = getFormattedDate(time);
    
    my $msg .= "```css\n========== $timestamp ============\n";
    $msg .= "Name: $name [$class]\n";
    $msg .= "Map: $map ($x, $y)\n";
    $msg .= "Base Lv: $bLv ($bExp%)\n";
    $msg .= "Job Lv: $jLv ($jExp%)\n";
    $msg .= "HP: $hp% | SP: $sp%\n";
    $msg .= "Guild: " . ($guild ? $guild : 'None') . "\n";
    $msg .= "Party: " . ($party ? "$party ($partyCount/12) [$partyExpShare]" : 'None') . "\n";
    $msg .= "\n";
    $msg .= "AI: " . ($ai ? $ai : 'None') . "\n";
    $msg .= "============================================\n```";
    return $msg;
}

sub discordPostMessage {
    # How to get discord webhook: https://techwiser.com/create-discord-webhook-send-message
    my ($msg) = @_;
    my $webHook = $config{discord_webhook};
    my $charName = $char->{name};
	my %content = ('username' => "OpenKore", 'content' => $msg);
    my $res = $ua->post($webHook, 
        'User-Agent' => 'discordbot-perl',
        'Content-Type' => 'application/json',
        'Content' => encode_json(\%content)
    );
}

sub discordGetMessage {
    my ($token, $channel) = @_;
    my $apiUrl = $baseUrl . "channels/$channel/messages?limit=1";

    my $res = $ua->get($apiUrl,
        'User-Agent' => 'discordbot-perl', 
        'Content-Type' => 'application/json',
        'Authorization' => "Bot $token"
    );

    if ($res->is_success) {
        my $content = decode_json($res->decoded_content);
        my $msgID = $content->[0]->{'id'}; # Message ID
        my $msgAuthor = $content->[0]->{'author'}->{'username'};
		my $msgAuthorID = $content->[0]->{'author'}->{'id'}; #username
		my $msgContent = $content->[0]->{'content'};
        my $timestamp = $content->[0]->{'timestamp'};
        if ($msgID > $lastMsgID && $msgAuthor !~ /OpenKore/i) {
            error(sprintf("[Discord-bot] -> %s: %s\n", $msgAuthor, $msgContent), 'openkore-discord');
            $lastMsg = $msgContent;
            $lastMsgUser = $msgAuthor;
            $lastMsgID = $msgID;
            my $logHook = Log::addHook(\&logDiscord, $lastMsgUser);

            # Split $msgContent into spaces
            my @msg = split(/\s+/, $msgContent);

            # Lowercase first element of @msg
            my $command = lc($msg[0]);

            # Add the rest of message to command separated by spaces
            $command .= ' ' . join(' ', @msg[1..$#msg]);

            Commands::run($command);
            Log::delHook($logHook);
        }
    } else {
        error(sprintf("[Discord-bot] -> %s\n", $res->status_line), 'openkore-discord');
    }
}

1;