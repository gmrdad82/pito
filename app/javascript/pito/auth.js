// Reads authentication state from the server-rendered gate element.
// The element is replaced via Turbo Stream after /login success.
export function isAuthenticated() {
  return document.getElementById("pito-auth-gate")?.dataset.authenticated === "true"
}
