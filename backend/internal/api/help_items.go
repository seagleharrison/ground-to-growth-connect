package api

import "fmt"

// The basic items a person can ask for. They pick from this list rather than
// typing, so a request can't carry anything personal. The app has the same
// list (lib/util/supply_items.dart); a test keeps them in step.
type supplyItem struct{ Code, Label string }

var supplyItems = []supplyItem{
	{"meal", "A meal"},
	{"water", "Water"},
	{"snacks", "Snacks"},
	{"socks", "Socks"},
	{"underwear", "Underwear"},
	{"shirt", "A shirt"},
	{"pants", "Pants"},
	{"shoes", "Shoes"},
	{"coat", "A coat or jacket"},
	{"hat_gloves", "A hat and gloves"},
	{"rain_poncho", "A rain poncho"},
	{"blanket", "A blanket"},
	{"sleeping_bag", "A sleeping bag"},
	{"tent_tarp", "A tent or tarp"},
	{"backpack", "A backpack"},
	{"hygiene_kit", "A hygiene kit"},
	{"feminine", "Feminine hygiene products"},
	{"diapers", "Diapers or baby supplies"},
	{"towel", "A towel"},
	{"first_aid", "First aid supplies"},
	{"phone_charger", "A phone charger"},
	{"bug_spray", "Bug spray or sunscreen"},
}

const maxSupplyItems = 10

// storedCategory is how a request's category is kept in the database. A
// supplies request is stored as "other" with its item list, which avoids
// changing the table's list of allowed categories on a live database.
func storedCategory(category string) string {
	if category == "supplies" {
		return "other"
	}
	return category
}

// cleanSupplyItems checks a picked list: at least one, no repeats, only items
// on the list, and not too many. It returns the list in the order the items
// appear above, so a request always reads the same way.
func cleanSupplyItems(picked []string) ([]string, string) {
	known := map[string]bool{}
	for _, it := range supplyItems {
		known[it.Code] = true
	}
	chosen := map[string]bool{}
	for _, code := range picked {
		if !known[code] {
			return nil, fmt.Sprintf("%q isn't something you can ask for here.", code)
		}
		chosen[code] = true
	}
	if len(chosen) == 0 {
		return nil, "Pick at least one thing you need."
	}
	if len(chosen) > maxSupplyItems {
		return nil, fmt.Sprintf("Ask for up to %d things at a time.", maxSupplyItems)
	}
	var out []string
	for _, it := range supplyItems {
		if chosen[it.Code] {
			out = append(out, it.Code)
		}
	}
	return out, ""
}
