import 'package:dartis/dartis.dart';
import 'dart:io' show Platform;
import 'package:uuid/uuid.dart';

import '../deck/deck.dart';

import 'dart:convert';

Client client;

initDatabase() async {
  try {
    client = await Client.connect(Platform.environment["REDIS_URL"]);
  } catch (e) {
    print(e);
  }
}

Future<String> startGame(String activePlayer, List<String> players) async {
  final gameID = Uuid().v4();
  var deck = Deck();

  var commands = client.asCommands<String, String>();

  players = [activePlayer, ...players];

  await Future.forEach(players, (p) async {
    // Set active game for all players
    await commands.set("users:${p}:activeGame", gameID);
    // Deal out cards to all players
    await commands.set("games:${gameID}:players:${p}:hand",
        json.encode(deck.dealOutCards(7).map((e) => e.toJson()).toList()));
  });

  await commands.set("games:${gameID}:players", json.encode(players));

  Card starterCard = deck.dealOutCards(1)[0];

  await commands.set("games:${gameID}:draw",
      json.encode(deck.cards.map((e) => e.toJson()).toList()));
  await commands.set(
      "games:${gameID}:discard", json.encode([starterCard.toJson()]));

  await commands.set("games:${gameID}:activePlayer", activePlayer);
  await commands.set(
      "games:${gameID}:activeColor", Card.ColorToString(starterCard.color));

  return gameID;
}

Future<String> getActiveGame(String user) async {
  return await client
      .asCommands<String, String>()
      .get("users:${user}:activeGame");
}

setActiveGame(String user, String gameID) async {
  await client
      .asCommands<String, String>()
      .set("users:${user}:activeGame", gameID);
}

removeActiveGame(String user) async {
  await client
      .asCommands<String, String>()
      .del(key: "users:${user}:activeGame");
}

class Game {
  final String game;
  Game(this.game);

  Future<List<Card>> getPlayerHand(String user) async {
    dynamic stuff = json.decode(await client
        .asCommands<String, String>()
        .get("games:${game}:players:${user}:hand"));
    stuff = stuff.map<Card>((v) => Card.fromJson(v)).toList();
    return stuff;
  }

  Future<Card> getTopCard() async {
    var discard =
        await client.asCommands<String, String>().get("games:${game}:discard");

    return Card.fromJson(json.decode(discard).last);
  }

  Future<List<Player>> getPlayers() async {
    var players = json
        .decode(await client
            .asCommands<String, String>()
            .get("games:${game}:players"))
        .cast<String>();

    List<Player> newList = [];

    await Future.forEach(players, (player) async {
      newList.add(Player(name: player, hand: await getPlayerHand(player)));
    });

    return newList;
  }

  Future<Player> getActivePlayer() async {
    var player = await client
        .asCommands<String, String>()
        .get("games:${game}:activePlayer");
    var hand = await getPlayerHand(player);

    return Player(name: player, hand: hand);
  }

  setActivePlayer(String player) async {
    await client
        .asCommands<String, String>()
        .set("games:${game}:activePlayer", player);
  }

  nextPlayer() async {
    var players = await getPlayers();
    var activePlayer = await getActivePlayer();

    if (activePlayer.name == players.last.name) {
      await setActivePlayer(players.first.name);
    } else {
      await setActivePlayer(
          players[players.indexWhere((e) => e.name == activePlayer.name) + 1]
              .name);
    }
  }

  end() async {
    var players = await getPlayers();
    Future.forEach<Player>(players, (e) async {
      await removeActiveGame(e.name);
    });
  }
}

class Player {
  final String name;
  final List<Card> hand;

  Player({this.name, this.hand});

  String toString() => this.name;
}
