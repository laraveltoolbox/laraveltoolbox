// The audience here lives on the keyboard: `/` or ⌘K jumps straight into the
// search field, Escape leaves it again. Whichever field is actually on screen
// wins - the navbar one on inner pages, the hero one on the landing page,
// where the navbar menu is collapsed behind the burger.
export default function SearchShortcut() {
  const inputs = Array.from(document.querySelectorAll(".search-form input[name=q]"))
  if (inputs.length === 0) return

  // offsetParent is null for anything display:none, which is how bulma hides
  // the navbar menu below its breakpoint
  const visibleInput = () => inputs.find((input) => input.offsetParent !== null)

  const isTyping = (element) =>
    element.isContentEditable || ["INPUT", "TEXTAREA", "SELECT"].includes(element.tagName)

  document.addEventListener("keydown", (event) => {
    if (event.key === "Escape" && inputs.includes(document.activeElement)) {
      document.activeElement.blur()
      return
    }

    const shortcut =
      (event.key === "/" && !event.metaKey && !event.ctrlKey && !isTyping(event.target)) ||
      (event.key === "k" && (event.metaKey || event.ctrlKey))

    if (!shortcut) return

    const input = visibleInput()
    if (!input) return

    event.preventDefault()
    input.focus()
    input.select()
  })
}
