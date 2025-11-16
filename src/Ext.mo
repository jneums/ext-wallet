// This is a generated Motoko binding.
// Please use `import service "ic:canister_id"` instead to call canisters on the IC if possible.

module {
  public type AccountIdentifier = Text;
  public type AccountIdentifier__1 = Text;
  public type Asset = {
    id : Nat32;
    name : Text;
    ctype : Text;
    canister : Text;
  };
  public type AssetHandle = Text;
  public type Balance = Nat;
  public type BalanceRequest = { token : TokenIdentifier; user : User };
  public type BalanceResponse = { #ok : Balance; #err : CommonError__1 };
  public type Balance__1 = Nat;
  public type BulkTransferRequest = {
    to : User;
    notify : Bool;
    from : User;
    memo : Memo;
    subaccount : ?SubAccount;
    tokens : [TokenIdentifier];
    amount : Balance;
  };
  public type CommonError = { #InvalidToken : TokenIdentifier; #Other : Text };
  public type CommonError__1 = {
    #InvalidToken : TokenIdentifier;
    #Other : Text;
  };
  public type Extension = Text;
  public type HeaderField = (Text, Text);
  public type HttpRequest = {
    url : Text;
    method : Text;
    body : Blob;
    headers : [HeaderField];
  };
  public type HttpResponse = {
    body : Blob;
    headers : [HeaderField];
    streaming_strategy : ?HttpStreamingStrategy;
    status_code : Nat16;
  };
  public type HttpStreamingCallbackResponse = {
    token : ?HttpStreamingCallbackToken;
    body : Blob;
  };
  public type HttpStreamingCallbackToken = {
    key : Text;
    sha256 : ?Blob;
    index : Nat;
    content_encoding : Text;
  };
  public type HttpStreamingStrategy = {
    #Callback : {
      token : HttpStreamingCallbackToken;
      callback : shared query HttpStreamingCallbackToken -> async HttpStreamingCallbackResponse;
    };
  };
  public type ListRequest = {
    token : TokenIdentifier__1;
    from_subaccount : ?SubAccount__1;
    price : ?Nat64;
  };
  public type Listing = { locked : ?Time; seller : Principal; price : Nat64 };
  public type Memo = Blob;
  public type Metadata = {
    #fungible : {
      decimals : Nat8;
      metadata : ?Blob;
      name : Text;
      symbol : Text;
    };
    #nonfungible : { metadata : ?Blob };
  };
  public type Result = {
    #ok : [(TokenIndex, ?Listing, ?Blob)];
    #err : CommonError;
  };
  public type Result_1 = { #ok : [TokenIndex]; #err : CommonError };
  public type Result_2 = { #ok : Balance__1; #err : CommonError };
  public type Result_3 = { #ok; #err : CommonError };
  public type Result_4 = { #ok : Metadata; #err : CommonError };
  public type Result_5 = { #ok : AccountIdentifier__1; #err : CommonError };
  public type Result_6 = {
    #ok : (AccountIdentifier__1, ?Listing);
    #err : CommonError;
  };
  public type Settlement = {
    subaccount : SubAccount__1;
    seller : Principal;
    buyer : AccountIdentifier__1;
    price : Nat64;
  };
  public type SubAccount = Blob;
  public type SubAccount__1 = Blob;
  public type Time = Int;
  public type TokenIdentifier = Text;
  public type TokenIdentifier__1 = Text;
  public type TokenIndex = Nat32;
  public type Transaction = {
    token : TokenIdentifier__1;
    time : Time;
    seller : Principal;
    buyer : AccountIdentifier__1;
    price : Nat64;
  };
  public type TransferRequest = {
    to : User;
    token : TokenIdentifier;
    notify : Bool;
    from : User;
    memo : Memo;
    subaccount : ?SubAccount;
    amount : Balance;
  };
  public type TransferResponse = {
    #ok : Balance;
    #err : {
      #CannotNotify : AccountIdentifier;
      #InsufficientBalance;
      #InvalidToken : TokenIdentifier;
      #Rejected;
      #Unauthorized : AccountIdentifier;
      #Other : Text;
    };
  };
  public type User = { #principal : Principal; #address : AccountIdentifier };
  public type Self = actor {
    acceptCycles : shared () -> async ();
    addAsset : shared (AssetHandle, Nat32, Text, Text, Text) -> async ();
    addThumbnail : shared (AssetHandle, Blob) -> async ();
    adminKillHeartbeat : shared () -> async ();
    adminRefund : shared (
      Text,
      AccountIdentifier__1,
      AccountIdentifier__1,
    ) -> async Text;
    adminStartHeartbeat : shared () -> async ();
    allPayments : shared query () -> async [(Principal, [SubAccount__1])];
    allSettlements : shared query () -> async [(TokenIndex, Settlement)];
    assetTokenMap : shared query () -> async [(AssetHandle, TokenIndex)];
    assetsToTokens : shared query [AssetHandle] -> async [TokenIndex];
    availableCycles : shared query () -> async Nat;
    balance : shared query BalanceRequest -> async BalanceResponse;
    bearer : shared query TokenIdentifier__1 -> async Result_5;
    clearPayments : shared (Principal, [SubAccount__1]) -> async ();
    cronCapEvents : shared () -> async ();
    cronDisbursements : shared () -> async ();
    cronSettlements : shared () -> async ();
    details : shared query TokenIdentifier__1 -> async Result_6;
    extensions : shared query () -> async [Extension];
    getAssets : shared query () -> async [(AssetHandle, Asset)];
    getMinter : shared query () -> async Principal;
    getNextSubAccount : shared query () -> async Nat;
    getRegistry : shared query () -> async [(TokenIndex, AccountIdentifier__1)];
    getThumbs : shared query () -> async [AssetHandle];
    getTokens : shared query () -> async [(TokenIndex, Metadata)];
    get_royalty_address : shared query () -> async Text;
    heartbeat_external : shared () -> async ();
    heartbeat_isRunning : shared query () -> async Bool;
    heartbeat_pending : shared query () -> async [(Text, Nat)];
    historicExport : shared () -> async Bool;
    http_request : shared query HttpRequest -> async HttpResponse;
    initCap : shared () -> async ();
    list : shared ListRequest -> async Result_3;
    listings : shared query () -> async [(TokenIndex, Listing, Metadata)];
    lock : shared (
      TokenIdentifier__1,
      Nat64,
      AccountIdentifier__1,
      SubAccount__1,
    ) -> async Result_5;
    metadata : shared query TokenIdentifier__1 -> async Result_4;
    payments : shared query () -> async ?[SubAccount__1];
    setMinter : shared Principal -> async ();
    settle : shared TokenIdentifier__1 -> async Result_3;
    settlements : shared query () -> async [(TokenIndex, AccountIdentifier__1, Nat64)];
    stats : shared query () -> async (
      Nat64,
      Nat64,
      Nat64,
      Nat64,
      Nat,
      Nat,
      Nat,
    );
    supply : shared query TokenIdentifier__1 -> async Result_2;
    toAddress : shared query (Text, Nat) -> async AccountIdentifier__1;
    tokens : shared query AccountIdentifier__1 -> async Result_1;
    tokens_ext : shared query AccountIdentifier__1 -> async Result;
    transactions : shared query () -> async [Transaction];
    transfer : shared TransferRequest -> async TransferResponse;
    transferBulk : shared BulkTransferRequest -> async TransferResponse;
  };
};
