# Changelog

## 2.2.0
- The cart carries its own paint catalog now. The "pick a dye" link slides
  it out beside the cart with every dye in the picker's categories, so dyes
  can be carted from anywhere, no house editor needed.
- Without Auctionator the AH button no longer stops at the browse list, it
  lands straight on the item's purchase page with the planned amount
  preset. The game grumbles an internal auction house error over a preset
  amount even though the buy goes through fine, so that one message is
  hidden while a preset is in play. Real errors still show.
- The windows remember where you dragged them between sessions, and the
  cart also keeps its size.
- A Ctrl-click add flies all ten icons into the cart instead of five.

## 2.1.0
- Cart items now get crossed off no matter where they come from. An auction
  win pulled from the mailbox, a crafted piece, a trade, anything that lands
  in your bags counts against the list, not just vendor buys.
- Dyes can go in the cart. Hover a swatch in the dye picker while
  customizing decor and hit the + (or Ctrl-click), click again to plan
  more, or drag a dye item in from your bags. A vendor selling a carted dye
  records its price like any decor piece. Dye rows draw compact, and decor
  rows got tighter too.
- At the auction house, carted items with no known vendor price show an AH
  button. With Auctionator installed it searches through the shopping tab
  with the planned counts attached, and a Search AH button runs the whole
  unpriced list at once. Without Auctionator the button searches too, with
  the results landing in the stock browse list. Buying a carted dye ticks
  the list the moment the purchase goes through, and collecting the
  delivery from the mail later will not tick it twice. The cart opens by
  itself at the AH when something unpriced is on the list, same as at a
  stocked vendor.
- While no decor is selected, the drop zone offers an "or add from the
  catalog" link. It opens the housing dashboard on the catalog tab, where
  the + buttons live.

## 2.0.1
- The addon list title is now "QoLify: Standalone Decor Tools", matching how
  the rest of the QoLify family is named. Nothing else changed.

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
