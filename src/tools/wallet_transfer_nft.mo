import Result "mo:base/Result";
import Principal "mo:base/Principal";
import Nat32 "mo:base/Nat32";
import Text "mo:base/Text";
import Blob "mo:base/Blob";

import McpTypes "mo:mcp-motoko-sdk/mcp/Types";
import AuthTypes "mo:mcp-motoko-sdk/auth/Types";
import Json "mo:json";

import Ext "../Ext";
import ExtIntegration "../ExtIntegration";

module {
  public func config() : McpTypes.Tool = {
    name = "wallet_transfer_nft";
    title = ?"Transfer NFT";
    description = ?"Transfer an EXT NFT from this wallet to another account ID. Only the wallet owner can use this tool.";
    payment = null;
    inputSchema = Json.obj([
      ("type", Json.str("object")),
      ("properties", Json.obj([("collection_canister", Json.obj([("type", Json.str("string")), ("description", Json.str("The canister ID of the NFT collection"))])), ("token_index", Json.obj([("type", Json.str("number")), ("description", Json.str("The token index to transfer"))])), ("to_account_id", Json.obj([("type", Json.str("string")), ("description", Json.str("The destination account ID (64-character hex string)"))])), ("to_principal", Json.obj([("type", Json.str("string")), ("description", Json.str("The destination principal ID (alternative to to_account_id)"))]))])),
      ("required", Json.arr([Json.str("collection_canister"), Json.str("token_index")])),
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
        return makeError("Only the wallet owner can transfer NFTs");
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

      let toAccountIdInput = Result.toOption(Json.getAsText(_args, "to_account_id"));
      let toPrincipalInput = Result.toOption(Json.getAsText(_args, "to_principal"));

      // User must provide exactly one destination
      let toAccountId = switch (toAccountIdInput, toPrincipalInput) {
        case (?accountId, null) {
          // Validate account ID format
          if (Text.size(accountId) != 64) {
            return makeError("Invalid account ID format. Must be 64-character hex string");
          };
          accountId;
        };
        case (null, ?principal) {
          // Convert principal to account ID
          let toPrincipal = try {
            Principal.fromText(principal);
          } catch (_) {
            return makeError("Invalid principal format");
          };
          ExtIntegration.principalToAccountIdentifier(toPrincipal, null);
        };
        case (null, null) {
          return makeError("Must provide either to_account_id or to_principal");
        };
        case (_, _) {
          return makeError("Cannot provide both to_account_id and to_principal. Choose one.");
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

      // Execute transfer
      let transferResult = try {
        await extCanister.transfer({
          from = #address(walletAccountId);
          to = #address(toAccountId);
          token = tokenIdentifier;
          amount = 1;
          memo = Blob.fromArray([]);
          notify = false;
          subaccount = null;
        });
      } catch (_) {
        return makeError("Transfer failed");
      };

      switch (transferResult) {
        case (#err(err)) {
          let errorMsg = switch (err) {
            case (#Unauthorized(aid)) { "Unauthorized: " # aid };
            case (#InsufficientBalance) { "Insufficient balance" };
            case (#Rejected) { "Transfer rejected" };
            case (#InvalidToken(tid)) { "Invalid token: " # tid };
            case (#CannotNotify(aid)) { "Cannot notify: " # aid };
            case (#Other(msg)) { "Transfer failed: " # msg };
          };
          return makeError(errorMsg);
        };
        case (#ok(_)) {
          let structuredPayload = Json.obj([
            ("token_index", Json.str(Nat32.toText(tokenIndex))),
            ("collection", Json.str(collectionCanisterText)),
            ("from", Json.str(walletAccountId)),
            ("to", Json.str(toAccountId)),
          ]);

          cb(#ok({ content = [#text({ text = Json.stringify(structuredPayload, null) })]; isError = false; structuredContent = ?structuredPayload }));
        };
      };
    };
  };
};
