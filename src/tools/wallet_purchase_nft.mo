import Principal "mo:base/Principal";
import Result "mo:base/Result";
import Text "mo:base/Text";
import Nat32 "mo:base/Nat32";
import Nat64 "mo:base/Nat64";
import Nat "mo:base/Nat";
import Blob "mo:base/Blob";
import Error "mo:base/Error";
import Time "mo:base/Time";
import Int "mo:base/Int";

import McpTypes "mo:mcp-motoko-sdk/mcp/Types";
import AuthTypes "mo:mcp-motoko-sdk/auth/Types";
import Json "mo:json";
import Base16 "mo:base16/Base16";

import Ext "../Ext";
import ExtIntegration "../ExtIntegration";

module {
  public type TransferFromArgs = {
    spender_subaccount : ?Blob;
    from : { owner : Principal; subaccount : ?Blob };
    to : { owner : Principal; subaccount : ?Blob };
    amount : Nat;
    fee : ?Nat;
    memo : ?Blob;
    created_at_time : ?Nat64;
  };

  public type TransferFromResult = {
    #Ok : Nat;
    #Err : {
      #InsufficientFunds : { balance : Nat };
      #InsufficientAllowance : { allowance : Nat };
      #BadFee : { expected_fee : Nat };
      #GenericError : { message : Text; error_code : Nat };
    };
  };

  public type TransferArgs = {
    to : Blob;
    fee : { e8s : Nat64 };
    memo : Nat64;
    from_subaccount : ?Blob;
    created_at_time : ?{ timestamp_nanos : Nat64 };
    amount : { e8s : Nat64 };
  };

  public type TransferResult = {
    #Ok : Nat64;
    #Err : {
      #InsufficientFunds : { balance : { e8s : Nat64 } };
      #BadFee : { expected_fee : { e8s : Nat64 } };
      #TxTooOld : { allowed_window_nanos : Nat64 };
      #TxCreatedInFuture;
      #TxDuplicate : { duplicate_of : Nat64 };
    };
  };

  public func config() : McpTypes.Tool = {
    name = "wallet_purchase_nft";
    title = ?"Purchase NFT";
    description = ?"Purchase an EXT NFT from the marketplace. Only the wallet owner can use this tool.";
    payment = null;
    inputSchema = Json.obj([
      ("type", Json.str("object")),
      ("properties", Json.obj([("collection_canister", Json.obj([("type", Json.str("string")), ("description", Json.str("The canister ID of the NFT collection"))])), ("token_index", Json.obj([("type", Json.str("number")), ("description", Json.str("The token index to purchase"))]))])),
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
        return makeError("Only the wallet owner can purchase NFTs");
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

      let collectionCanister = try {
        Principal.fromText(collectionCanisterText);
      } catch (_) {
        return makeError("Invalid canister principal");
      };

      let extCanister : Ext.Self = actor (Principal.toText(collectionCanister));

      // Get listing details
      let tokenId = ExtIntegration.encodeTokenIdentifier(tokenIndex, collectionCanister);
      let detailsResult = try {
        await extCanister.details(tokenId);
      } catch (_) {
        return makeError("Failed to fetch listing details");
      };

      let (_accountId, listingOpt) = switch (detailsResult) {
        case (#ok(details)) { details };
        case (#err(#InvalidToken(_))) {
          return makeError("Invalid token index: " # Nat32.toText(tokenIndex));
        };
        case (#err(#Other(msg))) {
          return makeError("Error fetching listing: " # msg);
        };
      };

      let listing = switch (listingOpt) {
        case (?l) { l };
        case (null) {
          return makeError("Token #" # Nat32.toText(tokenIndex) # " is not currently listed for sale");
        };
      };

      // Wallet account identifier (where NFT will be sent)
      let walletAccountId = ExtIntegration.principalToAccountIdentifier(walletPrincipal, null);

      try {
        // Lock the NFT for purchase
        let lockResult = await extCanister.lock(
          tokenId,
          listing.price,
          walletAccountId,
          Blob.fromArray([]), // No subaccount for wallet
        );

        switch (lockResult) {
          case (#err(#InvalidToken(_))) {
            return makeError("Invalid token");
          };
          case (#err(#Other(msg))) {
            return makeError("Failed to lock NFT: " # msg);
          };
          case (#ok(paymentAddress)) {
            // NFT is locked, proceed with payment using ICRC-2 + legacy transfer

            // Create ICP ledger actor
            let icpLedger = actor ("ryjl3-tyaaa-aaaaa-aaaba-cai") : actor {
              icrc2_transfer_from : shared TransferFromArgs -> async TransferFromResult;
              transfer : shared TransferArgs -> async TransferResult;
            };

            // Convert payment address to Blob
            let paymentAddressBlob = switch (Base16.decode(paymentAddress)) {
              case (?blob) { blob };
              case (null) {
                return makeError("Invalid payment address format: " # paymentAddress);
              };
            };

            // Step 1: Transfer from user to wallet using ICRC-2
            let walletAccount = {
              owner = walletPrincipal;
              subaccount = null;
            };

            let transferFromArgs : TransferFromArgs = {
              spender_subaccount = null;
              from = {
                owner = userPrincipal;
                subaccount = null;
              };
              to = walletAccount;
              amount = Nat64.toNat(listing.price) + 10_000; // listing price + transfer fee
              fee = null;
              memo = null;
              created_at_time = ?Nat64.fromNat(Int.abs(Time.now()));
            };

            let transferFromResult = await icpLedger.icrc2_transfer_from(transferFromArgs);

            switch (transferFromResult) {
              case (#Ok(blockIndex1)) {
                // Step 2: Transfer from wallet to marketplace payment address
                let transferArgs : TransferArgs = {
                  to = paymentAddressBlob;
                  fee = { e8s = 10_000 };
                  memo = 0;
                  from_subaccount = null;
                  created_at_time = ?{
                    timestamp_nanos = Nat64.fromNat(Int.abs(Time.now()));
                  };
                  amount = { e8s = listing.price };
                };

                let transferResult = await icpLedger.transfer(transferArgs);

                switch (transferResult) {
                  case (#Ok(blockIndex2)) {
                    // Payment successful, now settle the NFT
                    let settleResult = await extCanister.settle(tokenId);

                    switch (settleResult) {
                      case (#ok(())) {
                        let priceIcp = Nat64.toText(listing.price / 100_000_000) # "." # Nat64.toText((listing.price % 100_000_000) / 1_000_000);

                        let structuredPayload = Json.obj([
                          ("token_index", Json.str(Nat32.toText(tokenIndex))),
                          ("collection", Json.str(collectionCanisterText)),
                          ("price_e8s", Json.str(Nat64.toText(listing.price))),
                          ("price_icp", Json.str(priceIcp)),
                          ("block_index_1", Json.str(Nat.toText(blockIndex1))),
                          ("block_index_2", Json.str(Nat64.toText(blockIndex2))),
                        ]);

                        cb(#ok({ content = [#text({ text = Json.stringify(structuredPayload, null) })]; isError = false; structuredContent = ?structuredPayload }));
                      };
                      case (#err(#InvalidToken(_))) {
                        return makeError("Payment sent but settlement failed: Invalid token");
                      };
                      case (#err(#Other(msg))) {
                        return makeError("Payment sent but settlement failed: " # msg);
                      };
                    };
                  };
                  case (#Err(error)) {
                    let errorMsg = switch (error) {
                      case (#InsufficientFunds({ balance })) {
                        "Insufficient funds in wallet. Balance: " # Nat64.toText(balance.e8s) # " e8s";
                      };
                      case (#BadFee({ expected_fee })) {
                        "Bad fee. Expected: " # Nat64.toText(expected_fee.e8s) # " e8s";
                      };
                      case (#TxTooOld({ allowed_window_nanos })) {
                        "Transaction too old. Allowed window: " # Nat64.toText(allowed_window_nanos) # " nanos";
                      };
                      case (#TxCreatedInFuture) {
                        "Transaction created in future";
                      };
                      case (#TxDuplicate({ duplicate_of })) {
                        "Duplicate transaction: " # Nat64.toText(duplicate_of);
                      };
                    };
                    return makeError("Transfer to marketplace failed: " # errorMsg);
                  };
                };
              };
              case (#Err(error)) {
                let errorMsg = switch (error) {
                  case (#InsufficientFunds({ balance })) {
                    "Insufficient ICP balance. Your balance: " # Nat.toText(balance) # " e8s";
                  };
                  case (#InsufficientAllowance({ allowance })) {
                    "Insufficient allowance. Please approve the wallet canister to spend ICP on your behalf. Current allowance: " # Nat.toText(allowance) # " e8s";
                  };
                  case (#BadFee({ expected_fee })) {
                    "Bad fee. Expected: " # Nat.toText(expected_fee) # " e8s";
                  };
                  case (#GenericError({ message; error_code = _ })) {
                    "Transfer error: " # message;
                  };
                };
                return makeError(errorMsg);
              };
            };
          };
        };

      } catch (e) {
        return makeError("Purchase failed: " # Error.message(e));
      };
    };
  };
};
