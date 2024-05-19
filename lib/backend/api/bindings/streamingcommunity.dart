import 'dart:convert';

import 'package:stronzflix/backend/api/bindings/vixxcloud.dart';
import 'package:stronzflix/backend/api/media.dart';
import 'package:stronzflix/backend/api/site.dart';
import 'package:stronzflix/utils/simple_http.dart' as http;

class StreamingCommunity extends Site {

    static Site instance = StreamingCommunity._("https://streamingcommunity.foo");

    StreamingCommunity._(String url)
        : _cdn = url.replaceFirst("//", "//cdn."), _inhertia = {}, super("StreamingCommunity", url);

    final String _cdn;
    final Map<String, String> _inhertia;

    @override
    bool get allowsDownload => true;

    @override
    Future<void> construct() async {
        await this.getInhertia();
    }

    Future<void> getInhertia() async {
        String body = await http.get(super.url);
        RegExpMatch match = RegExp(r'version&quot;:&quot;(?<inertia>[a-z0-9]+)&quot;').firstMatch(body)!;
        this._inhertia["X-Inertia"] = "true";
        this._inhertia["X-Inertia-Version"] = match.namedGroup("inertia")!;
    }

    Future<List<TitleMetadata>> _fetch(String url) async {
        String body = await http.get("${super.url}${url}", headers: this._inhertia);
        dynamic json = jsonDecode(body);
        dynamic titles = json["props"]["titles"];

        List<TitleMetadata> results = [];
        for (dynamic title in titles) {
            String poster = title["images"].firstWhere((dynamic image) => image["type"] == "poster")["filename"];

            results.add(TitleMetadata(
                site: this,
                name: title["name"],
                url: "/titles/${title["id"]}-${title["slug"]}",
                poster:  "${this._cdn}/images/${poster}" 
            ));
        }

        return results;
    }

    @override
    Future<List<TitleMetadata>> search(String query) {
        return this._fetch("/search?q=${Uri.encodeQueryComponent(query)}");
    }

    @override
    Future<List<TitleMetadata>> latests() {
        return this._fetch("/browse/latest");
    }

    Future<Film> getFilm(TitleMetadata metadata, dynamic title) async {
        String banner = title["images"].firstWhere((dynamic image) => image["type"] == "cover_mobile")["filename"];
        
        return Film(
            player: VixxCloud.instance,
            url: "/watch/${title["id"]}",
            banner: "${this._cdn}/images/${banner}",
            description: title["plot"],
            metadata: metadata
        );
    }

    Future<List<Episode>> getEpisodes(Season season, String seasonUrl) async {
        String body = await http.get("${super.url}${seasonUrl}", headers: this._inhertia);
        dynamic json = jsonDecode(body);

        dynamic seasonObject = json["props"]["loadedSeason"];
        dynamic titleId = json["props"]["title"]["id"];

        return [
            for(dynamic episode in seasonObject["episodes"])
                Episode(
                    player: VixxCloud.instance,
                    url: "/watch/${titleId}?e=${episode["id"]}",
                    name: episode["name"],
                    cover: "${this._cdn}/images/${episode["images"].firstWhere((dynamic image) => image["type"] == "cover")["filename"]}",
                    season: season
                )
        ];
    }

    Future<Series> getSeries(TitleMetadata metadata, dynamic title) async {
        String banner = title["images"].firstWhere((dynamic image) => image["type"] == "cover_mobile")["filename"];
        
        Series series = Series(
            metadata: metadata,
            banner: "${this._cdn}/images/${banner}",
            description: title["plot"],
            seasons: [],
        );

        List<Season> seasons = [];
        for(var seasonObject in title["seasons"]) {
            Season season = Season(
                series: series,
                name: seasonObject["name"] ?? "Stagione ${seasonObject["number"]}",
                episodes: []
            );

            season.episodes.addAll(
                await this.getEpisodes(season, "/titles/${title["id"]}-${title["slug"]}/stagione-${seasonObject["number"]}")
            );

            seasons.add(season);
        }
        series.seasons.addAll(seasons);

        return series;
    }

    @override
    Future<Title> getTitle(TitleMetadata metadata) async {
        String body = await http.get("${super.url}${metadata.url}", headers: this._inhertia);
        dynamic json = jsonDecode(body);
        dynamic title = json["props"]["title"];

        if(title["type"] == "tv")
            return this.getSeries(metadata, title);
        else
            return this.getFilm(metadata, title);
    }
}