# EXT Wallet

A complete EXT NFT wallet with integrated marketplace functionality, built as a Motoko MCP server for the [Prometheus Protocol](https://prometheusprotocol.org) ecosystem.

**Why EXT Wallet?** Designed for AI agents to autonomously manage NFTs on your behalf. While traditional wallets require manual UI interactions, this wallet exposes all marketplace operations through simple tool calls, enabling agents to buy, sell, and transfer NFTs based on your goals.

## Features

- 🛒 **Browse & Purchase** - Explore marketplace listings with sorting and filtering, buy NFTs instantly
- 💰 **List for Sale** - Put your NFTs on the marketplace with flexible pricing, or delist anytime
- 📤 **Transfer Anywhere** - Send NFTs to any principal or account ID, including subaccounts
- 👀 **View Collection** - See your NFT collection and active marketplace listings with pagination
- 🔍 **Explore Marketplace** - Browse all listings sorted by price or filtered by seller

This guide assumes you are using `npm` as your package manager.

## Prerequisites

Before you begin, make sure you have the following tools installed on your system:

1.  **DFX:** The DFINITY Canister SDK. [Installation Guide](https://internetcomputer.org/docs/current/developer-docs/setup/install/).
2.  **Node.js:** Version 18.0 or higher. [Download](https://nodejs.org/).
3.  **MOPS:** The Motoko Package Manager. [Installation Guide](https://mops.one/docs/install).
4.  **Git:** The version control system. [Download](https://git-scm.com/).

---

## Part 1: Quick Start (Local Development)

This section guides you from zero to a working, testable MCP server on your local machine.

### Step 1: Initialize Your Repository

The Prometheus publishing process is tied to your Git history. Initialize a repository and make your first commit now.

```bash
git init
git add .
git commit -m "Initial commit from template"
```

### Step 2: Install Dependencies

This command will install both the required Node.js packages and the Motoko packages.

```bash
npm install
npm run mops:install
```

### Step 3: Deploy Your Server Locally

1.  **Start the Local Replica:** (Skip this if it's already running)
    ```bash
    npm run start
    ```
2.  **Deploy to the Local Replica:** (In a new terminal window)
    ```bash
    npm run deploy
    ```

### Step 4: Test with the MCP Inspector

Your wallet is live with all 7 NFT management tools ready to use:
- `wallet_get_id` - Get your wallet's principal and account ID
- `wallet_show_nfts` - View your NFT collection
- `wallet_transfer_nft` - Transfer NFTs to any account
- `wallet_list_nft_for_sale` - List/delist NFTs on the marketplace
- `wallet_my_listings` - View your active marketplace listings
- `wallet_explore_marketplace` - Browse all marketplace listings
- `wallet_purchase_nft` - Buy NFTs from the marketplace

1.  **Launch the Inspector:**
    ```bash
    npm run inspector
    ```
2.  **Connect to Your Canister:** Use the local canister ID endpoint provided in the `npm run deploy` output.
    ```
    # Replace `your_canister_id` with the actual ID from the deploy output
    http://127.0.0.1:4943/mcp/?canisterId=your_canister_id
    ```

### Step 5: Run the Test Suite

Your template includes a comprehensive test suite that validates all MCP server requirements.

```bash
npm test
```

The test suite verifies:
- ✅ **Tool Discovery (JSON-RPC)** - Tools are discoverable via the `/mcp` endpoint
- ✅ **Owner System** - Canister has proper owner management (`get_owner`, `set_owner`)
- ✅ **Wallet/Treasury System** - Treasury balance queries work (`get_treasury_balance`)
- ✅ **ICRC-120 Upgrade System** - Upgrade status reporting for App Store compatibility
- ✅ **API Key System** - Authentication works for paid tools (optional for public servers)

**Watch mode** for development:
```bash
npm run test:watch
```

🎉 **Congratulations!** You have a working local MCP server.

---

## Part 2: Using the Wallet

### Owner-Only Tools

These tools require authentication and can only be called by the wallet owner:
- `wallet_transfer_nft` - Transfer NFTs out of the wallet
- `wallet_list_nft_for_sale` - List/delist your NFTs on the marketplace  
- `wallet_purchase_nft` - Buy NFTs from the marketplace

### Public Tools

Anyone can call these to view wallet information:
- `wallet_get_id` - Get the wallet's principal and account ID
- `wallet_show_nfts` - View the wallet's NFT collection
- `wallet_my_listings` - See the wallet's active marketplace listings
- `wallet_explore_marketplace` - Browse all marketplace listings

### Example: Transferring an NFT

```bash
# Transfer to a principal (will be converted to account ID automatically)
dfx canister call <canister_id> wallet_transfer_nft '(
  record {
    collection_canister = "bzsui-sqaaa-aaaah-qce2a-cai";
    token_index = 4079;
    to_principal = opt principal "xxxxx-xxxxx-xxxxx-xxxxx-xxx";
    to_account_id = null;
  }
)'

# Or transfer directly to an account ID (64-char hex string)
dfx canister call <canister_id> wallet_transfer_nft '(
  record {
    collection_canister = "bzsui-sqaaa-aaaah-qce2a-cai";
    token_index = 4079;
    to_principal = null;
    to_account_id = opt "90eda23edc68c4248cc33a68be2bf80b77e9eb807ce7c66b156abd6d165e90a1";
  }
)'
```

---

## Part 3: Publish to the App Store (Deploy to Mainnet)

Instead of deploying to mainnet yourself, you publish your service to the Prometheus Protocol. The protocol then verifies, audits, and deploys your code for you.

### Step 1: Commit Your Changes

Make sure all your code changes (like enabling monetization) are committed to Git.

```bash
git add .
git commit -m "feat: enable monetization"
```

### Step 2: Publish Your Service

Use the `app-store` CLI to submit your service for verification and deployment.

```bash
# 1. Get your commit hash
git rev-parse HEAD
```

```bash
# 2. Run the init command to create your manifest
npm run app-store init 
```

Complete the prompts to set up your `prometheus.yml` manifest file.
Add your commit hash and the path to your WASM file (found in `.dfx/local/canisters/<your_canister_name>/<your_canister_name>.wasm`).

```bash
# 3. Run the publish command with your app version
npm run app-store publish "0.1.0"
```

Once your service passes the audit, the protocol will automatically deploy it and provide you with a mainnet canister ID. You can monitor the status on the **Prometheus Audit Hub**.

---

## Part 4: Managing Your Live Server

### Treasury Management

Your canister includes built-in Treasury functions to securely manage the funds it collects. You can call these with `dfx` against your **mainnet canister ID**.

-   `get_owner()`
-   `get_treasury_balance(ledger_id)`
-   `withdraw(ledger_id, amount, destination)`

### Updating Your Service (e.g., Enabling the Beacon)

Any code change to a live service requires publishing a new version.

1.  Open `src/main.mo` and uncomment the `beaconContext`.
2.  Commit the change: `git commit -m "feat: enable usage beacon"`.
3.  Re-run the **publishing process** from Part 3 with the new commit hash.

---

## Architecture

### Tool Structure

Each wallet tool is implemented as a separate module in `src/tools/`:
- `wallet_get_id.mo` - Returns wallet principal and account ID
- `wallet_show_nfts.mo` - Lists owned NFTs with cursor pagination (max 5 per page)
- `wallet_transfer_nft.mo` - Transfers NFTs to principals or account IDs
- `wallet_list_nft_for_sale.mo` - Lists/delists NFTs on marketplace
- `wallet_my_listings.mo` - Shows wallet's active marketplace listings
- `wallet_explore_marketplace.mo` - Browses all marketplace listings with sort/filter
- `wallet_purchase_nft.mo` - Purchases NFTs using ICRC-2 + legacy transfer

### EXT Integration

The wallet integrates with EXT NFT canisters through:
- `src/Ext.mo` - EXT standard type definitions
- `src/ExtIntegration.mo` - Helper functions for account ID conversions and EXT operations

### Payment Flow

NFT purchases use a two-step payment process:
1. **ICRC-2 Transfer**: User approves allowance, wallet pulls funds via `icrc2_transfer_from`
2. **Legacy Transfer**: Wallet pays marketplace using legacy ICP transfer
3. **Settlement**: Marketplace settles the transaction and transfers NFT to wallet

## What's Next?

-   **Add Collections:** The wallet supports any EXT NFT collection - just use different `collection_canister` IDs
-   **Run Tests:** Use `npm test` to ensure your changes meet all MCP server requirements
-   **Learn More:** Check out the full [Service Developer Docs](https://prometheusprotocol.org/docs) for advanced topics

---

## Testing

### Test Suite Overview

The template includes a comprehensive test suite (`test/prometheus.test.ts`) that validates your MCP server meets all requirements for the Prometheus Protocol App Store.

**What's tested:**
1. **JSON-RPC Tool Discovery** - Verifies tools are discoverable via HTTP endpoint
2. **Owner System** - Confirms owner management functions work correctly
3. **Wallet/Treasury System** - Validates treasury balance queries
4. **ICRC-120 Upgrade System** - Ensures compatibility with App Store upgrade process
5. **API Key System** - Tests authentication for paid tools (if enabled)
6. **Complete Integration** - End-to-end validation of all requirements

### Running Tests

```bash
# Run tests once
npm test

# Watch mode for development
npm run test:watch
```

### Test Output

When all tests pass, you'll see:
```
✅ MCP Server Requirements Summary:
   📡 Tool Discovery (JSON-RPC): ✅
   👤 Owner System: ✅
   💰 Wallet/Treasury System: ✅
   🔄 ICRC-120 Upgrade: ✅
```

### Adding Custom Tests

The template includes comprehensive tests in `test/prometheus.test.ts` and wallet-specific tests in `test/tools.test.ts`. When you add new tools, follow the existing pattern to test their specific functionality.

**Example: Testing wallet tools**

```typescript
describe('wallet_show_nfts Tool', () => {
  it('should return owned NFTs with pagination', async () => {
    const rpcPayload = {
      jsonrpc: '2.0',
      method: 'tools/call',
      params: {
        name: 'wallet_show_nfts',
        arguments: { 
          collection_canister: 'bzsui-sqaaa-aaaah-qce2a-cai',
          cursor: null
        }
      },
      id: 'test-show-nfts',
    };
    
    const responseBody = await callTool(rpcPayload);
    
    expect(responseBody.result.isError).toBe(false);
    const result = JSON.parse(responseBody.result.content[0].text);
    expect(result.total_owned).toBeGreaterThanOrEqual(0);
    expect(result.tokens).toBeDefined();
    expect(result.showing).toBeLessThanOrEqual(5); // Max page size
  });
});
```

See `test/tools.test.ts` for complete examples of testing wallet operations.