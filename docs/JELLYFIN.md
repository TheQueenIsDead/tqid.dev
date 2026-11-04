# Jellyfin events

Jellyfin's logs say when someone logs in, but not what they watched. The official
[Webhook plugin](https://github.com/jellyfin/jellyfin-plugin-webhook) posts an event for each
playback start and stop, login and new item to Alloy
([`etc/alloy/jellyfin.alloy`](../etc/alloy/jellyfin.alloy)), which sends it to Loki. The
**Jellyfin** dashboard in Grafana is built from them.

Query them with `{job="jellyfin/webhook"} | json`. `event` is a label.

## Plugin settings

The plugin is configured in Jellyfin, not in this repo. Install **Webhook** from **Dashboard >
Plugins > Catalog**, restart Jellyfin, then under **Dashboard > Plugins > Webhook** add a
**Generic Destination**:

| Setting | Value |
| --- | --- |
| Webhook Url | `http://host.docker.internal:3500/loki/api/v1/raw` |
| Notification Type | Authentication Failure, Authentication Success, Item Added, Playback Start, Playback Stop |
| Item Type | Movies, Episodes |
| Send All Properties | Off |
| Trim leading and trailing whitespace | On |
| Skip empty message body | On |

Leave Playback Progress off: it fires every few seconds while something plays.

Template. It must stay on **one line**, as the endpoint stores each line as a separate entry:

```handlebars
{"event":"{{NotificationType}}","user":"{{NotificationUsername}}","username":"{{Username}}","type":"{{ItemType}}","name":"{{Name}}","series":"{{SeriesName}}","season":"{{SeasonNumber00}}","episode":"{{EpisodeNumber00}}","year":"{{Year}}","client":"{{ClientName}}","device":"{{DeviceName}}","ip":"{{RemoteEndPoint}}","completed":"{{PlayedToCompletion}}","position":"{{PlaybackPosition}}","runtime":"{{RunTime}}"}
```

Fields an event doesn't have come out empty. Failed logins fill `username` rather than `user`.

## Checking it

From the NUC, this should print `204` and show up in Loki as a `test` event:

```shell
docker exec jellyfin curl -s -o /dev/null -w '%{http_code}\n' -X POST \
  --data '{"event":"test"}' http://host.docker.internal:3500/loki/api/v1/raw
```

`ip` is the address Jellyfin sees, which is Traefik's rather than the viewer's unless Jellyfin
trusts Traefik as a proxy (**Dashboard > Networking > Known proxies**). Traefik's access logs
have the real address (`request_Cf_Connecting_Ip`).
