# Changelog

## 2.0.0
- Renamed to Decor Tools. The spend watching stays as it was, and a decor
  shopping cart joins it.
- The cart is a wish list for decor, opened with /cart. Catalog entries get a
  small + button in the house editor storage and on the housing dashboard, a
  decor selected in edit mode can be dropped in by clicking the cart box, and
  decor items drag in from bags. Shift adds 5 at once, Ctrl 10.
- Carted items show their price. The catalog gives an estimate, marked with ~,
  and visiting a vendor that sells the item records the real cost, whether
  gold, a currency, barter items or a mix. Hovering a cost icon tells you what
  it is, and the footer sums up the whole plan.
- At a vendor, carted items carry a "buy N" tooltip line that counts down as
  you buy. Rows grow a Buy button for items the open vendor sells, and Buy all
  buys everything it can at three a second, with a confirm step first.
- Walking up to a vendor that stocks something from the cart opens the cart by
  itself, and leaving closes it again unless you had it open already.
- The cart stays up in house edit mode, closes on Escape and resizes from its
  bottom right corner.
- The minimap button opens the cart on left click and the spend watcher on
  right click.

## 1.1.0
- Cap warning now only shows on decor, not every item over the cap at a decor vendor.

## 1.0.0
- First release.
