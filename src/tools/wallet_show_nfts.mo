import Result "mo:base/Result";
import Principal "mo:base/Principal";
import Text "mo:base/Text";
import Nat "mo:base/Nat";
import Nat32 "mo:base/Nat32";
import Array "mo:base/Array";
import Iter "mo:base/Iter";

import McpTypes "mo:mcp-motoko-sdk/mcp/Types";
import AuthTypes "mo:mcp-motoko-sdk/auth/Types";
import Json "mo:json";

import Ext "../Ext";
import ExtIntegration "../ExtIntegration";

module {
  public func config() : McpTypes.Tool = {
    name = "wallet_show_nfts";
    title = ?"Show NFTs";
    description = ?"Show all EXT NFTs owned by this wallet canister";
    payment = null;
    inputSchema = Json.obj([
      ("type", Json.str("object")),
      ("properties", Json.obj([("collection_canister", Json.obj([("type", Json.str("string")), ("description", Json.str("The canister ID of the NFT collection"))])), ("cursor", Json.obj([("type", Json.str("number")), ("description", Json.str("Optional cursor for pagination (token index to start from)"))]))])),
      ("required", Json.arr([Json.str("collection_canister")])),
    ]);
    outputSchema = null;
  };

  public func handle(walletPrincipal : Principal) : (
    _args : McpTypes.JsonValue,
    _auth : ?AuthTypes.AuthInfo,
    cb : (Result.Result<McpTypes.CallToolResult, McpTypes.HandlerError>) -> (),
  ) -> async () {
    func(_args : McpTypes.JsonValue, _auth : ?AuthTypes.AuthInfo, cb : (Result.Result<McpTypes.CallToolResult, McpTypes.HandlerError>) -> ()) : async () {

      func makeError(message : Text) {
        cb(#ok({ content = [#text({ text = "Error: " # message })]; isError = true; structuredContent = null }));
      };

      // Parse collection canister
      let collectionCanisterText = switch (Result.toOption(Json.getAsText(_args, "collection_canister"))) {
        case (?t) { t };
        case (null) {
          return makeError("Missing collection_canister parameter");
        };
      };

      // Parse optional cursor
      let cursor : Nat32 = switch (Result.toOption(Json.getAsNat(_args, "cursor"))) {
        case (?n) { Nat32.fromNat(n) };
        case (null) { 0 };
      };

      let collectionCanister = try {
        Principal.fromText(collectionCanisterText);
      } catch (_) {
        return makeError("Invalid canister principal");
      };

      let extCanister : Ext.Self = actor (Principal.toText(collectionCanister));

      // Get wallet's account ID
      let walletAccountId = ExtIntegration.principalToAccountIdentifier(walletPrincipal, null);

      // Query tokens owned by this wallet
      let tokensResult = try {
        await extCanister.tokens(walletAccountId);
      } catch (_) {
        return makeError("Failed to query NFTs from collection");
      };

      let allTokens = switch (tokensResult) {
        case (#err(#InvalidToken(t))) {
          return makeError("Invalid token: " # t);
        };
        case (#err(#Other(msg))) {
          // "No tokens" is a valid empty result, not an error
          if (msg == "No tokens") {
            [];
          } else {
            return makeError("Query failed: " # msg);
          };
        };
        case (#ok(tokens)) { tokens };
      };

      // Apply pagination: filter tokens >= cursor and take max 5
      let maxResults : Nat = 5;
      let filteredTokens = Array.filter<Nat32>(allTokens, func(t : Nat32) : Bool { t >= cursor });
      let sortedTokens = Array.sort<Nat32>(filteredTokens, Nat32.compare);
      let pageTokens = if (sortedTokens.size() > maxResults) {
        Iter.toArray(Array.slice(sortedTokens, 0, maxResults));
      } else {
        sortedTokens;
      };

      let hasMore = sortedTokens.size() > maxResults;
      let nextCursor = if (hasMore and pageTokens.size() > 0) {
        ?(pageTokens[pageTokens.size() - 1] + 1);
      } else {
        null;
      };

      // Build token list for JSON
      let tokenJsonArray = Array.map<Nat32, Json.Json>(
        pageTokens,
        func(t) { Json.str(Nat32.toText(t)) },
      );

      let structuredPayload = Json.obj([
        ("wallet_principal", Json.str(Principal.toText(walletPrincipal))),
        ("wallet_account_id", Json.str(walletAccountId)),
        ("collection", Json.str(collectionCanisterText)),
        ("total_owned", Json.str(Nat.toText(allTokens.size()))),
        ("showing", Json.str(Nat.toText(pageTokens.size()))),
        ("tokens", Json.arr(tokenJsonArray)),
        (
          "next_cursor",
          switch (nextCursor) {
            case (?n) { Json.str(Nat32.toText(n)) };
            case (null) { Json.nullable() };
          },
        ),
      ]);

      cb(#ok({ content = [#text({ text = Json.stringify(structuredPayload, null) })]; isError = false; structuredContent = ?structuredPayload }));
    };
  };
};
