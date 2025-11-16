import Result "mo:base/Result";
import Principal "mo:base/Principal";

import McpTypes "mo:mcp-motoko-sdk/mcp/Types";
import AuthTypes "mo:mcp-motoko-sdk/auth/Types";
import Json "mo:json";

import ExtIntegration "../ExtIntegration";

module {
  public func config() : McpTypes.Tool = {
    name = "wallet_get_id";
    title = ?"Get Wallet ID";
    description = ?"Get this wallet's principal and account ID for receiving NFTs";
    payment = null;
    inputSchema = Json.obj([
      ("type", Json.str("object")),
      ("properties", Json.obj([])),
    ]);
    outputSchema = null;
  };

  public func handle(walletPrincipal : Principal) : (
    _args : McpTypes.JsonValue,
    _auth : ?AuthTypes.AuthInfo,
    cb : (Result.Result<McpTypes.CallToolResult, McpTypes.HandlerError>) -> (),
  ) -> async () {
    func(_args : McpTypes.JsonValue, _auth : ?AuthTypes.AuthInfo, cb : (Result.Result<McpTypes.CallToolResult, McpTypes.HandlerError>) -> ()) : async () {

      // Get wallet's account ID
      let walletAccountId = ExtIntegration.principalToAccountIdentifier(walletPrincipal, null);
      let walletPrincipalText = Principal.toText(walletPrincipal);

      let structuredPayload = Json.obj([
        ("principal", Json.str(walletPrincipalText)),
        ("account_id", Json.str(walletAccountId)),
      ]);

      cb(#ok({ content = [#text({ text = Json.stringify(structuredPayload, null) })]; isError = false; structuredContent = ?structuredPayload }));
    };
  };
};
