// All user-facing English text lives here. Do not inline copy in components.
// Copy must be true. Do not add claims about money, verification, protection or contact unless they are operated.
export const strings = {
  appName: 'Mopani Corridor',
  pilotNotice: 'This is a pilot. Payments are not available yet.',
  configMissing:
    'This build cannot start because its configuration file is missing. Ask the team for the correct environment file.',
  configInvalid: 'This build cannot start because its configuration is not valid.',
  signInUnavailable:
    'Sign-in codes cannot be sent yet. You can look around, but you cannot place an order.',
} as const;

// Increment 2: browse and quote. Copy describes only what the app does today.
export const strings2 = {
  catalogHeading: 'Fresh produce',
  catalogEmpty: 'No produce is listed right now. Listings appear once sellers add stock.',
  catalogLoadError: 'The produce list could not be loaded. Try again later.',
  catalogDropped: 'Some listings could not be shown because their details are incomplete.',
  addToBasket: 'Add to basket',
  stockLabel: 'In stock',
  basketHeading: 'Your basket',
  basketEmpty: 'Your basket is empty.',
  increase: 'Add one',
  decrease: 'Remove one',
  remove: 'Remove',
  subtotalLabel: 'Product subtotal',
  subtotalNote: 'Delivery and your total are worked out when you get your total.',
  getTotal: 'Get my total',
  routesHeading: 'Delivery routes',
  routeMinimum: 'Minimum basket',
  routeFee: 'Delivery fee for each 5 kg or part, from',
  routesLoadError: 'Delivery route details could not be loaded.',
  quoteHeading: 'Your total',
  quoteProduct: 'Products',
  quoteDelivery: 'Delivery',
  quoteCard: 'Card processing fee',
  quoteTotal: 'Total',
  quoteShare: 'Delivery is about {pct}% of the product value.',
  quoteWeight: 'Weight: {kg} kg. Delivery is charged for {blocks} block(s) of up to 5 kg.',
  quoteNeedsSignIn:
    'Your total cannot be worked out yet, because sign-in codes cannot be sent yet. You can keep adding items.',
  quoteBelowMinimum:
    'This basket is below the minimum for this route. Add more items, or choose a different route.',
  quoteNoRoute: 'Delivery to this destination is not set up yet.',
  quoteStockChanged:
    'Some items are no longer available in this quantity. Please refresh the list.',
  quoteQuantity: 'Quantities must be between 1 and 50.',
  quoteLocalTownOnly: 'Local delivery is only for buyers in the same town as the seller.',
  quoteOneSellerOnly:
    'A delivery can only include items from one seller. Start a separate order for each seller.',
  quoteGeneric: 'We could not work out your total. Please try again.',
  basketErrorQuantity: 'You can order between 1 and 50 of an item.',
  basketErrorStock: 'You cannot add more than the stock available.',
  basketErrorOutOfStock: 'This item is out of stock.',
  paymentsHeading: 'Payment status',
  paymentsNotYet:
    'Payments are not available yet. When they open, each payment will show as pending until the payment provider confirms it.',
  paymentsSignIn: 'Sign in to see your payments. Sign-in codes cannot be sent yet.',
  paymentsNoWithdraw: 'Withdrawals are not available in this pilot.',
} as const;
