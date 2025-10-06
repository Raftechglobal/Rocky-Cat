
import "dotenv/config";
import { createWalletClient, createPublicClient, http, parseEther } from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { bscTestnet, bsc } from "viem/chains";
import RockyCatV2Artifact from "../artifacts/contracts/RockyCatV2.sol/RockyCatV2.json";

const PRIVATE_KEY = process.env.PRIVATE_KEY as `0x${string}`;
if (!PRIVATE_KEY) throw new Error("Missing PRIVATE_KEY in .env");

const NETWORK = process.env.NETWORK || "local"; // "local" | "testnet" | "mainnet"

let chain, rpcUrl;

const localChain = {
  id: 31337,
  name: "Localhost",
  network: "localhost",
  nativeCurrency: {
    name: "Ether",
    symbol: "ETH",
    decimals: 18,
  },
  rpcUrls: {
    default: { http: ["http://127.0.0.1:8545"] },
  },
  testnet: true,
};

switch (NETWORK) {
  case "local":
    chain = localChain;
    rpcUrl = localChain.rpcUrls.default.http[0];
    break;
  case "testnet":
    chain = bscTestnet;
    rpcUrl = "https://bsc-testnet-rpc.publicnode.com";
    break;
  case "mainnet":
    chain = bsc;
    rpcUrl = "https://bsc-rpc.com";
    break;
  default:
    throw new Error(`Unsupported NETWORK: ${NETWORK}`);
}


const account = privateKeyToAccount(PRIVATE_KEY);

const walletClient = createWalletClient({
  account,
  chain,
  transport: http(rpcUrl),
});

const publicClient = createPublicClient({
  chain,
  transport: http(rpcUrl),
});

async function main() {
  console.log(`🚀 Deploying on network: ${NETWORK}`);
  console.log("Using account:", account.address);

  // Deploy the contract
  const deployTx = await walletClient.deployContract({
    abi: RockyCatV2Artifact.abi,
    bytecode: RockyCatV2Artifact.bytecode,
    args: ["RockyCat", "RKCv2", 1_000_000_000, account.address],
  });

  console.log("⏳ Waiting for transaction:", deployTx);

  const receipt = await publicClient.waitForTransactionReceipt({ hash: deployTx });
  console.log("✅ Contract deployed at:", receipt.contractAddress);
}

main().catch((err) => {
  console.error("❌ Deployment failed:", err);
  process.exit(1);
});


// ===== HOW TO RUN =====

// # For local
// NETWORK=local npx tsx scripts/deploy.ts

// # For testnet
// NETWORK=testnet npx tsx scripts/deploy.ts

// # For mainnet
// NETWORK=mainnet npx tsx scripts/deploy.ts
