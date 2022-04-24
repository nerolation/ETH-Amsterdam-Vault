## ETH-Amsterdam-Vault

## This is the official repository of join(T)! 
* Using Voltz Protocol, join(T) allows for pooled, tokenized, and continuous IRS positions. Our contracts enable USDC deposits and withdrawals, no Aave downtime, and tradeable fixed rate positions.

### The tools involved in this project are the following:
* Truffle
* Hardhat
* Remix
* Kovan
* Tenderly

## join(T) in practice:
join(T) is an extension to the Voltz Protocol. Voltz Protocol allows users to enter interest rate swaps  (IRS): exchanging the risk and return of a variable rate yielding asset against the cash flow of a fixed rate position. As only cash flows are traded at maturity, risk is hedged by requiring collateralization only for the risk of those cash flows, creating synthetic leveraged risk swap positions. Users can also fully hedge their positions by posting 100% of the notional trade by entering a risk swap from a variable to a fixed rate and posting 100% of the collateral. This position incurs no risk. 

join(T) enables users to leverage such fully collateralized positions. We create new and liquid possibilities for risk portfolios through our pool tokens, ERC-20 jvUSDC, which represents the users’ share of returns from a specific strategy, entering continuously into new fixed-rate IRS.  Our contracts take USDC as input and enters an Aave lending pool. After an initial investing period, those aUSDC are used to enter a fixed rate interest swap via Voltz Protocol’s Full Collateralization Module. This enables users to take a fixed taker position, swapping the variable rate of aUSDC against a fixed rate, while requiring the user to only send in the USDC wanted as notional for the swap. After maturity of the entered fixed-rate position, any user can force the settlement of the pooled position. At this point, we realize a new exchange rate of the pool token jvUSDC against the updated pool balance, which our contract still controls as aUSDC. After settlement, users can participate in a phase enabling withdraw-to-burn and invest-to-mint. To withdraw, users can swap their jvUSDC, which are then burned, against their share of the pool balance, sent as USDC. By minting, a user effectively invests into the strategy of the pool for the next round, while paying the current exchange rate for newly minted jvUSDC. These funds are again used immediately to enter an Aave variable rate position to maximize time spent in a yield-earning state. After the funding round, the aUSDC are again entered into a fixed rate taker position, according to a pre-defined strategy.  

Typically, a fixed taker unwinds a position by entering the opposite side of the same trade, incurring overhead. Under join(T) they can now sell their tradeable share of the pooled strategy on the secondary market. This usability of the share of the pooled strategy presents opportunities for more complex financial mechanisms. For example, using an IRS as collateral, or by using equally created tokens representing the other leg of the trade to create further pools and (v)AMMs. 

join(T) currently implements one specific strategy, with a pre-defined vAMM to enter a position using all its funds, without accounting for information on current market expectations of changing variable or fixed interest rates, nor the optimal position size and efficient upper and lower bounds for funding rounds. Additionally, we are currently restricting to discrete funding and withdrawal periods to maintain a no-risk, fully collateralized position. Additional forms of risk portfolios could be implemented with various modifications on swap pool choice and position timing rules.

These strategies could be simulated for viability and parameterized into template risk swap positions, offered via a front-end to give users access to specific strategies, depending on their needs. By pooling various strategies together, users can then create complex risk portfolios or start new strategies on their own. Additionally, the mechanism could be used for automated risk strategies.  

As it stands, join(T) contributes to the potential Voltz Protocol strategy space and facilitates new usage patterns for Voltz users. We show the potential for modifiable pooled fund strategies, with options for varying continuous investment cycles and risk swap strategies through our Proof-of-Concept of one type of risk strategy investment through pooled funds, tradeable as tokenized positions. 


## The development of join(T):
### How did we build the project?
We approached Voltz Protocol and our extension of it from two sides. One part of our team analyzed the mechanisms used in Voltz through the codebase, testing // running on testnet and connecting functions to the overall financial mechanism. The other part of the team tackled interest rate swaps and their use and variations in traditional finance. Our first task was to truly understand the risk swap positions and why users would want to enter them. After an initial, sometimes confused understanding of potential strategies, we sketched out possible integrations and the respective required touchpoints with users, contracts, and data sources. We refined our understanding of the swap strategies by testing various functions and their results. After more information on swap results and their implications on portfolios was discovered, mainly through helpfully provided information by the Voltz Protocol team, we were able to sketch out a rough but complete lifecycle of our investment. This allowed us to plan potential modifiers for additional strategy variability and a continuous investment option. 

We were able to divide dev work on the ERC-20 token contract, the JointVaultStrategy Contract and integrations with Voltz and Aave for the yield bearing leg. 
After completing and testing our minting and burning interactions, and the integration with Voltz components such as the Full Collateralization Module, we created a first working round of a full investment cycle, including settlement. 

### What tech did we use?


### How do they interact
### How did sponsor tech benefit our project?
### Did you do anything “hacky” worth mentioning

### How were we impressed with our deliverable?
We were able to use the available repositories and testnet contracts for entering into interest rate swap positions and settling our positions. Our project extends potential capabilities, while requiring the Voltz Protocol for most base mechanisms. join(T) wraps a Voltz Protocol position strategy and plugs into the mechanisms to operationalize the risk swap for the tokenized and pooled investment. Using the Full Collateralization Module we avoid risk stemming from undercollateralized risk swap positions and are able to let our user invest USDC and withdraw USDC, while exposing themselves to a larger potential of risk variations realized through specific strategies. 


## Happy Hackathon
