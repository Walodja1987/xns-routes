/**
 * Deploy XNSRoutes
 *
 * USAGE:
 * `npx hardhat run scripts/deploy/deployXNSRoutes.ts --network sepolia`
 *
 * REQUIRED SETUP (Hardhat vars — see docs/DEV_NOTES.md):
 * - MNEMONIC
 * - ETHERSCAN_API_KEY (for verification on public networks)
 * - Network RPC, e.g. ETH_SEPOLIA_TESTNET_URL
 *
 * XNS registry (constructor arg):
 * - Preferred: `npx hardhat vars set XNS_CONTRACT_ADDRESS` (deployed XNS / resolver contract
 *   implementing IXNS: getAddress, isValidLabelOrNamespace, registerName)
 * - Override for one-off runs: `XNS_CONTRACT_ADDRESS=0x... npx hardhat run ...`
 *
 * After deployment, record the address in constants/addresses.ts (XNS_ROUTES_ADDRESS).
 *
 * The constructor is payable: it forwards `msg.value` to XNS `registerName("routes","xns")` so `routes.xns`
 * resolves to the new registry. The script queries `getNamespacePrice("xns")` on the XNS contract and
 * uses that as the deployment transaction value (excess is refunded by XNS).
 */

import { vars } from "hardhat/config";
import hre from "hardhat";
import { getAddress, isAddress } from "ethers";

const RESET = "\x1b[0m";
const GREEN = "\x1b[32m";
const YELLOW = "\x1b[33m";

function delay(ms: number) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function resolveXnsContractAddress(): string {
  const fromEnv = process.env.XNS_CONTRACT_ADDRESS?.trim();
  const raw = fromEnv && fromEnv.length > 0 ? fromEnv : vars.get("XNS_CONTRACT_ADDRESS");
  if (!isAddress(raw)) {
    throw new Error(
      "Set a valid XNS registry address via hardhat var XNS_CONTRACT_ADDRESS or env XNS_CONTRACT_ADDRESS.",
    );
  }
  return getAddress(raw);
}

function shouldVerifyOnExplorer(): boolean {
  const n = hre.network.name;
  return n !== "hardhat" && n !== "localhost";
}

async function main() {
  console.log("Deploying XNSRoutes...\n");

  const xnsAddress = resolveXnsContractAddress();
  console.log("XNS registry (constructor):", xnsAddress, "\n");

  const [deployer] = await hre.ethers.getSigners();
  console.log("Deploying with account:", deployer.address);
  console.log(
    "Account balance:",
    hre.ethers.formatEther(await hre.ethers.provider.getBalance(deployer.address)),
    "ETH\n",
  );

  const xnsPriceAbi = [
    "function getNamespacePrice(string namespace) external view returns (uint256)",
  ] as const;
  const xnsForPrice = new hre.ethers.Contract(xnsAddress, xnsPriceAbi, deployer);
  let registrationValue: bigint;
  try {
    registrationValue = await xnsForPrice.getNamespacePrice("xns");
    console.log(
      "XNS getNamespacePrice(\"xns\"):",
      hre.ethers.formatEther(registrationValue),
      "ETH (sent with deployment for registerName)\n",
    );
  } catch {
    throw new Error(
      "Could not read getNamespacePrice(\"xns\") on the XNS contract. Check XNS_CONTRACT_ADDRESS and network.",
    );
  }

  const XNSRoutes = await hre.ethers.getContractFactory("XNSRoutes");
  const xnsRoutes = await XNSRoutes.deploy(xnsAddress, { value: registrationValue });
  await xnsRoutes.waitForDeployment();

  const contractAddress = await xnsRoutes.getAddress();
  console.log("XNSRoutes deployed to:", `${GREEN}${contractAddress}${RESET}\n`);

  if (!shouldVerifyOnExplorer()) {
    console.log(
      `${YELLOW}Skipping block explorer verification (local network).${RESET}\n` +
        "Done. Update constants/addresses.ts with the address above if needed.",
    );
    return;
  }

  console.log(
    "Waiting 30 seconds before verification so the explorer can index the contract...\n",
  );
  await delay(30_000);

  try {
    await hre.run("verify:verify", {
      address: contractAddress,
      constructorArguments: [xnsAddress],
    });
    console.log("\nVerification succeeded.");
  } catch (err: unknown) {
    const msg = err instanceof Error ? err.message : String(err);
    if (msg.includes("Already Verified")) {
      console.log("\nContract already verified.");
    } else {
      throw err;
    }
  }

  console.log(
    "\nDeployment finished. Record the address in constants/addresses.ts (XNS_ROUTES_ADDRESS) if applicable.",
  );
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
