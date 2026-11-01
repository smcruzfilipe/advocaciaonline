export const displayName = 'Page Shell';
export const shortDescription = 'Page wrapper with padding and max width';

export default function PageShell({ children, maxWidth = 'max-w-5xl' }) {
  return (
    <main className={`w-full ${maxWidth} mx-auto px-8 py-8 font-body`}>
      {children}
    </main>
  );
}
