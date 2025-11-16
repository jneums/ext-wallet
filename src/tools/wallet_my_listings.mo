import Result "mo:base/Result";
import Principal "mo:base/Principal";
import Text "mo:base/Text";
import Nat "mo:base/Nat";
import Nat32 "mo:base/Nat32";
import Nat64 "mo:base/Nat64";
import Array "mo:base/Array";
import Iter "mo:base/Iter";

import McpTypes "mo:mcp-motoko-sdk/mcp/Types";
import AuthTypes "mo:mcp-motoko-sdk/auth/Types";
import Json "mo:json";

import Ext "../Ext";
import ExtIntegration "../ExtIntegration";

module {
  public func config() : McpTypes.Tool = {
    name = "wallet_my_listings";
    title = ?"My Listings";
    description = ?"Show NFTs from this wallet that are currently listed for sale";
    payment = null;
    inputSchema = Json.obj([
      ("type", Json.str("object")),
      ("properties", Json.obj([("collection_canister", Json.obj([("type", Json.str("string")), ("description", Json.str("The canister ID of the NFT collection"))])), ("cursor", Json.obj([("type", Json.str("number")), ("description", Json.str("Optional cursor for pagination (index to start from)"))]))])),
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
      let cursor : Nat = switch (Result.toOption(Json.getAsNat(_args, "cursor"))) {
        case (?n) { n };
        case (null) { 0 };
      };

      let collectionCanister = try {
        Principal.fromText(collectionCanisterText);
      } catch (_) {
        return makeError("Invalid canister principal");
      };

      let extCanister : Ext.Self = actor (Principal.toText(collectionCanister));

      // Query all listings from the marketplace
      let allListings = try {
        await extCanister.listings();
      } catch (_) {
        return makeError("Failed to query listings from collection");
      };

      // Filter to only this wallet's listings
      let myListings = Array.filter<(Nat32, Ext.Listing, Ext.Metadata)>(
        allListings,
        func((tokenIndex, listing, metadata)) {
          Principal.equal(listing.seller, walletPrincipal);
        },
      );

      // Apply pagination: skip cursor items and take max 5
      let maxResults : Nat = 5;
      let filteredListings = if (cursor > 0 and cursor < myListings.size()) {
        Iter.toArray(Array.slice(myListings, cursor, myListings.size()));
      } else if (cursor == 0) {
        myListings;
      } else {
        [];
      };

      let pageListings = if (filteredListings.size() > maxResults) {
        Iter.toArray(Array.slice(filteredListings, 0, maxResults));
      } else {
        filteredListings;
      };

      let nextCursor = if (cursor + pageListings.size() < myListings.size()) {
        ?(cursor + pageListings.size());
      } else {
        null;
      };

      // Build listings array for JSON
      let listingsJsonArray = Array.map<(Nat32, Ext.Listing, Ext.Metadata), Json.Json>(
        pageListings,
        func((tokenIndex, listing, _metadata)) {
          Json.obj([
            ("token_index", Json.str(Nat32.toText(tokenIndex))),
            ("price_e8s", Json.str(Nat64.toText(listing.price))),
            ("price_icp", Json.str(Nat64.toText(listing.price / 100_000_000) # "." # Nat64.toText((listing.price % 100_000_000) / 1_000_000))),
          ]);
        },
      );

      let structuredPayload = Json.obj([
        ("wallet_principal", Json.str(Principal.toText(walletPrincipal))),
        ("collection", Json.str(collectionCanisterText)),
        ("total_listings", Json.str(Nat.toText(myListings.size()))),
        ("showing", Json.str(Nat.toText(pageListings.size()))),
        ("listings", Json.arr(listingsJsonArray)),
        (
          "next_cursor",
          switch (nextCursor) {
            case (?n) { Json.str(Nat.toText(n)) };
            case (null) { Json.nullable() };
          },
        ),
      ]);

      cb(#ok({ content = [#text({ text = Json.stringify(structuredPayload, null) })]; isError = false; structuredContent = ?structuredPayload }));
    };
  };
};
