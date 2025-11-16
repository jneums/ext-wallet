import Result "mo:base/Result";
import Principal "mo:base/Principal";
import Nat32 "mo:base/Nat32";
import Nat64 "mo:base/Nat64";
import Text "mo:base/Text";

import McpTypes "mo:mcp-motoko-sdk/mcp/Types";
import AuthTypes "mo:mcp-motoko-sdk/auth/Types";
import Json "mo:json";

import Ext "../Ext";
import ExtIntegration "../ExtIntegration";

module {
  public func config() : McpTypes.Tool = {
    name = "wallet_list_nft_for_sale";
    title = ?"List NFT for Sale";
    description = ?"List an EXT NFT from this wallet for sale on the marketplace. Only the wallet owner can use this tool.";
    payment = null;
    inputSchema = Json.obj([
      ("type", Json.str("object")),
      ("properties", Json.obj([("collection_canister", Json.obj([("type", Json.str("string")), ("description", Json.str("The canister ID of the NFT collection"))])), ("token_index", Json.obj([("type", Json.str("number")), ("description", Json.str("The token index to list for sale"))])), ("price_e8s", Json.obj([("type", Json.str("number")), ("description", Json.str("The price in e8s (1 ICP = 100,000,000 e8s). Set to 0 to delist."))]))])),
      ("required", Json.arr([Json.str("collection_canister"), Json.str("token_index"), Json.str("price_e8s")])),
    ]);
    outputSchema = null;
  };

  public func handle(walletPrincipal : Principal, owner : Principal) : (
    _args : McpTypes.JsonValue,
    _auth : ?AuthTypes.AuthInfo,
    cb : (Result.Result<McpTypes.CallToolResult, McpTypes.HandlerError>) -> (),
  ) -> async () {
    func(_args : McpTypes.JsonValue, _auth : ?AuthTypes.AuthInfo, cb : (Result.Result<McpTypes.CallToolResult, McpTypes.HandlerError>) -> ()) : async () {

      func makeError(message : Text) {
        cb(#ok({ content = [#text({ text = "Error: " # message })]; isError = true; structuredContent = null }));
      };

      // Verify authentication and ownership
      let userPrincipal = switch (_auth) {
        case (?auth) { auth.principal };
        case (null) {
          return makeError("Authentication required");
        };
      };

      if (not Principal.equal(userPrincipal, owner)) {
        return makeError("Only the wallet owner can list NFTs for sale");
      };

      // Parse parameters
      let collectionCanisterText = switch (Result.toOption(Json.getAsText(_args, "collection_canister"))) {
        case (?t) { t };
        case (null) {
          return makeError("Missing collection_canister parameter");
        };
      };

      let tokenIndex = switch (Result.toOption(Json.getAsNat(_args, "token_index"))) {
        case (?n) { Nat32.fromNat(n) };
        case (null) {
          return makeError("Missing or invalid token_index parameter");
        };
      };

      let priceE8s = switch (Result.toOption(Json.getAsNat(_args, "price_e8s"))) {
        case (?n) { Nat64.fromNat(n) };
        case (null) {
          return makeError("Missing or invalid price_e8s parameter");
        };
      };

      let collectionCanister = try {
        Principal.fromText(collectionCanisterText);
      } catch (_) {
        return makeError("Invalid canister principal");
      };

      let extCanister : Ext.Self = actor (Principal.toText(collectionCanister));

      // Encode token identifier
      let tokenIdentifier = ExtIntegration.encodeTokenIdentifier(tokenIndex, collectionCanister);

      // Verify ownership
      let bearer = try {
        await extCanister.bearer(tokenIdentifier);
      } catch (_) {
        return makeError("Failed to verify ownership");
      };

      let walletAccountId = ExtIntegration.principalToAccountIdentifier(walletPrincipal, null);

      switch (bearer) {
        case (#err(_)) {
          return makeError("Token not found");
        };
        case (#ok(currentOwner)) {
          if (currentOwner != walletAccountId) {
            return makeError("Wallet does not own this NFT");
          };
        };
      };

      // Execute list request
      let priceOpt = if (priceE8s == 0) { null } else { ?priceE8s };

      let listResult = try {
        await extCanister.list({
          token = tokenIdentifier;
          from_subaccount = null;
          price = priceOpt;
        });
      } catch (_) {
        return makeError("List operation failed");
      };

      switch (listResult) {
        case (#err(err)) {
          let errorMsg = switch (err) {
            case (#InvalidToken(tid)) { "Invalid token: " # tid };
            case (#Other(msg)) { "List failed: " # msg };
          };
          return makeError(errorMsg);
        };
        case (#ok(_)) {
          let action = if (priceE8s == 0) { "delisted" } else {
            "listed for sale";
          };

          let structuredPayload = Json.obj([
            ("token_index", Json.str(Nat32.toText(tokenIndex))),
            ("collection", Json.str(collectionCanisterText)),
            ("price_e8s", Json.str(Nat64.toText(priceE8s))),
            ("action", Json.str(action)),
          ]);

          cb(#ok({ content = [#text({ text = Json.stringify(structuredPayload, null) })]; isError = false; structuredContent = ?structuredPayload }));
        };
      };
    };
  };
};
