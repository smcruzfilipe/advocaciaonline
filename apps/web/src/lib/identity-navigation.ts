type IdentityDestination = "/dashboard" | "/login" | "/auth/google";

export function navigateAfterIdentityChange(path: IdentityDestination): void {
  // A full same-origin navigation discards React state from the previous tenant.
  const destination = new URL(path, window.location.origin);
  window.location.assign(destination.href);
}
