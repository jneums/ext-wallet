import Nat "mo:base/Nat";
import Nat32 "mo:base/Nat32";
import Nat8 "mo:base/Nat8";
import Text "mo:base/Text";
import Array "mo:base/Array";
import Blob "mo:base/Blob";
import Principal "mo:base/Principal";
import Result "mo:base/Result";
import Hash "mo:base/Hash";
import Iter "mo:base/Iter";
import Nat64 "mo:base/Nat64";
import Buffer "mo:base/Buffer";
import AccountId "mo:account-identifier";
import Base16 "mo:base16/Base16";

module {
  // ===== EXT STANDARD TYPES =====

  public type TokenIndex = Nat32;
  public type TokenIdentifier = Text;
  public type AccountIdentifier = Text;

  public type TokenObj = {
    index : TokenIndex;
    canister : [Nat8];
  };

  // EXT standard result types
  public type CommonError = {
    #InvalidToken : TokenIdentifier;
    #Other : Text;
  };

  public type Result_5 = Result.Result<AccountIdentifier, CommonError>;
  public type Result_4 = Result.Result<Metadata, CommonError>;

  public type Metadata = {
    #fungible : {
      name : Text;
      symbol : Text;
      decimals : Nat8;
      metadata : ?Blob;
    };
    #nonfungible : {
      metadata : ?Blob;
    };
  };

  // ===== EXT TOKEN IDENTIFIER UTILITIES =====

  private let tds : [Nat8] = [10, 116, 105, 100]; //b"\x0Atid"

  private func bytestonat32(b : [Nat8]) : Nat32 {
    var index : Nat32 = 0;
    Array.foldRight<Nat8, Nat32>(
      b,
      0,
      func(u8, accum) {
        index += 1;
        accum + Nat32.fromNat(Nat8.toNat(u8)) << ((index - 1) * 8);
      },
    );
  };

  public func decodeTokenIdentifier(tid : TokenIdentifier) : TokenObj {
    let bytes = Blob.toArray(Principal.toBlob(Principal.fromText(tid)));
    var index : Nat8 = 0;
    var _canister : [Nat8] = [];
    var _token_index : [Nat8] = [];
    var _tdscheck : [Nat8] = [];
    var length : Nat8 = 0;
    for (b in bytes.vals()) {
      length += 1;
      if (length <= 4) {
        _tdscheck := Array.append(_tdscheck, [b]);
      };
      if (length == 4) {
        if (Array.equal(_tdscheck, tds, Nat8.equal) == false) {
          return {
            index = 0;
            canister = bytes;
          };
        };
      };
    };
    for (b in bytes.vals()) {
      index += 1;
      if (index >= 5) {
        if (index <= (length - 4)) {
          _canister := Array.append(_canister, [b]);
        } else {
          _token_index := Array.append(_token_index, [b]);
        };
      };
    };
    let v : TokenObj = {
      index = bytestonat32(_token_index);
      canister = _canister;
    };
    return v;
  };

  public func getTokenIndex(tid : TokenIdentifier) : TokenIndex {
    let tobj = decodeTokenIdentifier(tid);
    tobj.index;
  };

  // Encode a token index into a TokenIdentifier for the given canister
  public func encodeTokenIdentifier(tokenIndex : TokenIndex, canisterId : Principal) : TokenIdentifier {
    let canisterBytes = Blob.toArray(Principal.toBlob(canisterId));

    // Build the token identifier: [tds] [canister] [tokenIndex]
    let buffer = Buffer.Buffer<Nat8>(4 + canisterBytes.size() + 4);

    // Add TDS header
    buffer.add(10); // \x0A
    buffer.add(116); // t
    buffer.add(105); // i
    buffer.add(100); // d

    // Add canister bytes
    for (b in canisterBytes.vals()) {
      buffer.add(b);
    };

    // Add token index as 4 bytes (big-endian)
    buffer.add(Nat8.fromNat(Nat32.toNat((tokenIndex >> 24) & 0xFF)));
    buffer.add(Nat8.fromNat(Nat32.toNat((tokenIndex >> 16) & 0xFF)));
    buffer.add(Nat8.fromNat(Nat32.toNat((tokenIndex >> 8) & 0xFF)));
    buffer.add(Nat8.fromNat(Nat32.toNat(tokenIndex & 0xFF)));

    let blob = Blob.fromArray(Buffer.toArray(buffer));
    Principal.toText(Principal.fromBlob(blob));
  };

  // ===== EXT CANISTER INTERFACE =====

  // Transfer request types for EXT
  public type TransferRequest = {
    from : User;
    to : User;
    token : TokenIdentifier;
    amount : Nat;
    memo : Blob;
    notify : Bool;
    subaccount : ?SubAccount;
  };

  public type TransferResponse = Result.Result<Nat, { #Unauthorized : AccountIdentifier; #InsufficientBalance; #Rejected; #InvalidToken : TokenIdentifier; #CannotNotify : AccountIdentifier; #Other : Text }>;

  public type User = {
    #address : AccountIdentifier;
    #principal : Principal;
  };

  public type SubAccount = [Nat8];

  // Marketplace types
  public type Listing = {
    locked : ?Int; // Time
    seller : Principal;
    price : Nat64;
  };

  public type ListRequest = {
    token : TokenIdentifier;
    from_subaccount : ?Blob;
    price : ?Nat64;
  };

  public type Result_6 = Result.Result<(AccountIdentifier, ?Listing), CommonError>;

  // Interface to communicate with the PokedBots EXT canister
  public type ExtCanisterInterface = actor {
    // Get all token indices owned by an account
    tokens : shared query (AccountIdentifier) -> async Result.Result<[TokenIndex], CommonError>;

    // Get the owner of a specific token
    bearer : shared query (TokenIdentifier) -> async Result_5;

    // Get metadata for a token
    metadata : shared query (TokenIdentifier) -> async Result_4;

    // Transfer NFT
    transfer : shared (TransferRequest) -> async TransferResponse;

    // Marketplace methods
    listings : shared query () -> async [(TokenIndex, Listing, Metadata)];
    details : shared query (TokenIdentifier) -> async Result_6;
    lock : shared (TokenIdentifier, Nat64, AccountIdentifier, SubAccount) -> async Result_5;
    settle : shared (TokenIdentifier) -> async Result.Result<(), CommonError>;
    list : shared (ListRequest) -> async Result.Result<(), CommonError>;
  };

  // Helper to create EXT canister actor reference
  public func getExtCanister(canisterId : Principal) : ExtCanisterInterface {
    actor (Principal.toText(canisterId));
  };

  // Helper to check if a user owns a specific token
  public func verifyOwnership(
    extCanister : ExtCanisterInterface,
    tokenIdentifier : TokenIdentifier,
    expectedOwner : AccountIdentifier,
  ) : async Bool {
    try {
      let ownerResult = await extCanister.bearer(tokenIdentifier);
      switch (ownerResult) {
        case (#ok(owner)) { owner == expectedOwner };
        case (#err(_)) { false };
      };
    } catch (_e) {
      false;
    };
  };

  // Helper to get all tokens owned by a user
  public func getOwnedTokens(
    extCanister : ExtCanisterInterface,
    accountId : AccountIdentifier,
  ) : async Result.Result<[TokenIndex], Text> {
    try {
      let tokensResult = await extCanister.tokens(accountId);
      switch (tokensResult) {
        case (#ok(tokens)) { #ok(tokens) };
        case (#err(#InvalidToken(t))) { #err("Invalid token: " # t) };
        case (#err(#Other(msg))) { #err(msg) };
      };
    } catch (_e) {
      #err("Failed to fetch tokens from EXT canister");
    };
  };

  // ===== SUBACCOUNT UTILITIES =====

  // Derive a subaccount from a user's principal for their "garage"
  // Each user gets a unique subaccount where they can store their racing bots
  public func deriveGarageSubaccount(userPrincipal : Principal) : SubAccount {
    let principalBlob = Principal.toBlob(userPrincipal);
    let principalBytes = Blob.toArray(principalBlob);

    // Create a 32-byte subaccount
    // Format: [garage_tag (4 bytes)] [principal_bytes (up to 28 bytes, padded)]
    let buffer = Buffer.Buffer<Nat8>(32);

    // Add "GARG" tag (Garage)
    buffer.add(71); // G
    buffer.add(65); // A
    buffer.add(82); // R
    buffer.add(71); // G

    // Add principal bytes (padded/truncated to 28 bytes)
    var i = 0;
    while (i < 28) {
      if (i < principalBytes.size()) {
        buffer.add(principalBytes[i]);
      } else {
        // Pad with zeros if principal is shorter
        buffer.add(0);
      };
      i += 1;
    };

    Buffer.toArray(buffer);
  };

  // Convert principal + subaccount to EXT AccountIdentifier (hex string)
  public func principalToAccountIdentifier(p : Principal, subaccount : ?SubAccount) : AccountIdentifier {
    let subBlob = switch (subaccount) {
      case (null) { AccountId.defaultSubaccount() };
      case (?s) { Blob.fromArray(s) };
    };
    let accountBlob = AccountId.accountIdentifier(p, subBlob);
    Base16.encode(accountBlob);
  };
};
