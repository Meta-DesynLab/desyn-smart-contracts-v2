# Deploy Desyn with Hardhat

This repository contains the scripts to deploy the Desyn Core contracts to ethereum mainnet node.

In Scripts you will find also a test run (with no assertions) that can be run against a local node (much faster).

## Getting Started

Clone this repository 

```
https://github.com/Meta-DesynLab/desyn-smart-contracts-v2.git
cd desyn-smart-contracts-v2
``` 

Install dependencies:

```
npm i
```

For ethereum mainnet:

```
npx hardhat run --network mainnet scripts/deploy-desyn.js
```

You can also run the "test" with the following code:

```
npx hardhat run --network standalone scripts/test-around.js
```

Have fun :) 

