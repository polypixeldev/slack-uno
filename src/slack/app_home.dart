import '../deck/deck.dart';
import 'slack.dart';
import 'dart:io' show Platform;
import '../db/db.dart' as db;
import 'dart:convert';

updateAppHomeForAllInGame(String gameID) async {
  var players = await db.Game(gameID).getPlayers();
  await Future.forEach<db.Player>(players, (e) async {
    await updateAppHome(e.name);
  });
}

updateAppHome(String user) async {
  var client = SlackClient(Platform.environment["SLACK_TOKEN"]);

  final activeGame = await db.getActiveGame(user);

  var view = {
    "type": "home",
    "blocks": [
      {
        "type": "actions",
        "elements": [
          {
            "type": "button",
            "text": {
              "type": "plain_text",
              "emoji": true,
              "text": ":rocket: Start an Uno game"
            },
            "action_id": "start",
          }
        ],
      },
    ],
  };

  if (activeGame != null) {
    var game = db.Game(activeGame);

    final hand = await game.getPlayerHand(user);
    final topCard = await game.getTopCard();

    var url = Uri.https("slack-uno-renderer.vercel.app", "/api/image", {
      "hand": json.encode(hand),
      "table": json.encode(topCard),
    });

    final players = await game.getPlayers();
    final player = await game.getActivePlayer();

    final playableCards = hand
        .asMap()
        .entries
        .where((e) =>
            e.value.color == topCard.color || e.value.number == topCard.number)
        .toList();

    var winner = await game.getWinner();

    if (winner != null) {
      view = {
        "type": "home",
        "private_metadata": activeGame,
        "blocks": [
          {
            "type": "section",
            "text": {"type": "mrkdwn", "text": ":tada: <@${winner}> won!"},
            "accessory": {
              "type": "button",
              "text": {
                "type": "plain_text",
                "text": "End game",
              },
              "style": "danger",
              "action_id": "end"
            }
          }
        ],
      };
    } else {
      view = {
        "type": "home",
        "private_metadata": activeGame,
        "blocks": [
          {
            "type": "section",
            "text": {
              "type": "mrkdwn",
              "text": user == player.name
                  ? ":rotating_light: *It's your turn!* :rotating_light:"
                  : "It's <@${player.name}>'s turn."
            },
            "accessory": {
              "type": "button",
              "text": {
                "type": "plain_text",
                "text": "End game",
              },
              "style": "danger",
              "action_id": "end",
              "confirm": {
                "title": {"type": "plain_text", "text": "End game?"},
                "text": {
                  "type": "plain_text",
                  "text":
                      "Are you sure you'd like to end this game for all players?"
                },
                "confirm": {"type": "plain_text", "text": "End"},
                "deny": {"type": "plain_text", "text": "Cancel"},
                "style": "danger"
              }
            }
          },
          {
            "type": "image",
            "image_url": url.toString(),
            "alt_text": "stuff",
          },
          {
            "type": "header",
            "text": {"type": "plain_text", "text": "Playable Cards"}
          },
          ...playableCards.map<Map<String, dynamic>>((e) => {
                "type": "section",
                "text": {
                  "type": "mrkdwn",
                  "text": Card.ColorToEmoji(e.value.color) +
                      " *" +
                      e.value.number +
                      "*",
                },
                if (user == player.name)
                  "accessory": {
                    "type": "button",
                    "action_id": "play:${e.key}",
                    "value": e.key.toString(),
                    "text": {
                      "type": "plain_text",
                      "text": "Play Card",
                    }
                  }
              }),
          if (playableCards.length == 0 && user == player.name)
            {
              "type": "section",
              "text": {
                "type": "mrkdwn",
                "text":
                    "*You have no playable cards.* Click over there to draw one :arrow_right:"
              },
              "accessory": {
                "type": "button",
                "action_id": "draw",
                "text": {
                  "type": "plain_text",
                  "text": "Draw Card",
                }
              }
            },
          {
            "type": "context",
            "elements": [
              {
                "type": "mrkdwn",
                "text": "*Players:* " +
                    players
                        .map<String>(
                            (e) => "<@${e.name}> (${e.hand.length} cards)")
                        .toList()
                        .join(", "),
              }
            ]
          }
        ]
      };
    }
  }

  client.publishView(user, view);
}
