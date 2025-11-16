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

module {
  public func config() : McpTypes.Tool = {
    name = "wallet_explore_marketplace";
    title = ?"Explore Marketplace";
    description = ?"Browse all NFTs currently listed for sale on the marketplace";
    payment = null;
    inputSchema = Json.obj([
      ("type", Json.str("object")),
      ("properties", Json.obj([("collection_canister", Json.obj([("type", Json.str("string")), ("description", Json.str("The canister ID of the NFT collection"))])), ("sort_by", Json.obj([("type", Json.str("string")), ("description", Json.str("Optional: sort by 'price_asc', 'price_desc', or 'token_index' (default)"))])), ("seller_filter", Json.obj([("type", Json.str("string")), ("description", Json.str("Optional: filter by seller principal"))])), ("cursor", Json.obj([("type", Json.str("number")), ("description", Json.str("Optional cursor for pagination (index to start from)"))]))])),
      ("required", Json.arr([Json.str("collection_canister")])),
    ]);
    outputSchema = null;
  };

  public func handle(_walletPrincipal : Principal) : (
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

      // Parse optional sort_by
      let sortBy = Result.toOption(Json.getAsText(_args, "sort_by"));

      // Parse optional seller_filter
      let sellerFilter = Result.toOption(Json.getAsText(_args, "seller_filter"));

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

      // Apply seller filter if provided
      let filteredListings = switch (sellerFilter) {
        case (?sellerText) {
          let sellerPrincipal = try {
            Principal.fromText(sellerText);
          } catch (_) {
            return makeError("Invalid seller principal");
          };
          Array.filter<(Nat32, Ext.Listing, Ext.Metadata)>(
            allListings,
            func((_, listing, _)) {
              Principal.equal(listing.seller, sellerPrincipal);
            },
          );
        };
        case (null) { allListings };
      };

      // Apply sorting
      let sortedListings = switch (sortBy) {
        case (?"price_asc") {
          Array.sort<(Nat32, Ext.Listing, Ext.Metadata)>(
            filteredListings,
            func(a, b) { Nat64.compare(a.1.price, b.1.price) },
          );
        };
        case (?"price_desc") {
          Array.sort<(Nat32, Ext.Listing, Ext.Metadata)>(
            filteredListings,
            func(a, b) { Nat64.compare(b.1.price, a.1.price) },
          );
        };
        case (_) {
          // Default: sort by token_index
          Array.sort<(Nat32, Ext.Listing, Ext.Metadata)>(
            filteredListings,
            func(a, b) { Nat32.compare(a.0, b.0) },
          );
        };
      };

      // Apply pagination: skip cursor items and take max 5
      let maxResults : Nat = 5;
      let paginatedListings = if (cursor > 0 and cursor < sortedListings.size()) {
        Iter.toArray(Array.slice(sortedListings, cursor, sortedListings.size()));
      } else if (cursor == 0) {
        sortedListings;
      } else {
        [];
      };

      let pageListings = if (paginatedListings.size() > maxResults) {
        Iter.toArray(Array.slice(paginatedListings, 0, maxResults));
      } else {
        paginatedListings;
      };

      let nextCursor = if (cursor + pageListings.size() < sortedListings.size()) {
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
            ("seller", Json.str(Principal.toText(listing.seller))),
            ("price_e8s", Json.str(Nat64.toText(listing.price))),
            ("price_icp", Json.str(Nat64.toText(listing.price / 100_000_000) # "." # Nat64.toText((listing.price % 100_000_000) / 1_000_000))),
          ]);
        },
      );

      let structuredPayload = Json.obj([
        ("collection", Json.str(collectionCanisterText)),
        ("total_listings", Json.str(Nat.toText(sortedListings.size()))),
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
