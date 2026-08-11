# Decor Tools

Two tools for housing decor: a shopping cart you fill while decorating, and a
spending watcher so the decorating doesn't quietly empty your gold.

## The shopping cart

Type `/cart` or click the minimap coin. While you decorate, collect the pieces
you're missing: every catalog entry gets a small + button (in the house editor
storage and on the housing dashboard), the decor piece you have selected in
edit mode can be dropped straight into the cart box, and decor items or dyes
drag in from your bags. Shift adds 5 at once, Ctrl adds 10. Dyes can also be
carted right from the dye picker while customizing a piece: hover a swatch
and hit the +, or just Ctrl-click it, again for each extra one planned. Away
from your house, the "pick a dye" link slides a paint catalog out beside the
cart with every dye instead.

Carted items show their price. The catalog gives an estimate, marked with ~,
and visiting a vendor that sells a piece records its real cost, whether gold,
a currency, barter items or a mix. Hover a cost icon to see what it is, and
the footer sums up what the whole plan will run you, each part of the sum
green while you can cover it and red once you cannot. Hover the sum to put
what you carry beside what the cart asks for.

The list keeps itself sorted into sections, decor, dyes and blueprint
pieces, each collapsible behind its header. Drag the window wider and the
rows flow into columns.

At a vendor, anything from your list gets a "buy N" tooltip line that counts
down as you buy. Rows grow a Buy button for items the open vendor sells,
walking up to a vendor that stocks your items opens the cart by itself, and
each section's Buy all fetches everything it can at three purchases a
second, with a confirm click first so it never runs by accident. Hover that
button to price up what this vendor has of the section, colored the same
way, and if your purse falls short it says what is missing and how many
items will go through before it buys anything.

Pieces without a vendor still get ticked off: an auction win pulled from the
mailbox, a crafted piece, a trade, anything that lands in your bags counts
against the list. At the auction house the cart opens by itself when
something unpriced is on the list, and those items grow an AH button. With
Auctionator it searches through the shopping tab, planned counts included,
and each section header carries an AH search that runs its unpriced items
in one go. Without Auctionator the button takes you straight to the item's
purchase page with the planned amount preset. Buying a carted dye ticks the
list right at the purchase, and the mail delivery later will not tick it
twice.

From patch 12.1 blueprints feed the cart too. Blizzard's blueprint window
grows a Cart missing button for everything the blueprint needs that you do
not own, and a Cart all for the full set. The cart's own "add from a
blueprint" link opens a picker of your saved blueprints beside the window,
where single pieces add with their + (the missing count on a plain click,
the full count with Ctrl) and the same two buttons take the whole list.
Blueprint pieces sit in their own cart section apart from the hand-picked
ones, clicking a second time tops counts up instead of doubling them, and
stacking a genuine second set on top is one confirm away.

## The spend watcher

Type `/dsw` or right-click the minimap coin. Pick a per-item gold cap and
anything priced above it gets a red warning on its vendor tooltip, plus a
note in chat if you buy it anyway. A running total keeps track of what decor
has cost you so far.

## Part of QoLify

Decor Tools also ships as a module of
[QoLify](https://www.curseforge.com/wow/addons/qolify), my quality of life
suite. Install whichever you prefer, your settings follow you between them.
If both are installed, the standalone runs and the module stands by.
