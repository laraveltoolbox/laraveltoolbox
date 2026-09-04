// The reset button inside the search fields. Visibility is CSS's job (it keys
// off :placeholder-shown), so this only has to handle the click and hand focus
// back to the field the user was working in.
export default function SearchClear() {
  document.querySelectorAll(".search-form .clear-search").forEach((button) => {
    button.addEventListener("click", () => {
      const input = button.closest(".search-control").querySelector("input[name=q]")
      if (!input) return

      input.value = ""
      input.focus()
    })
  })
}
