import TopNav from "./TopNav";

function Layout({ children }) {
  return (
    <div className="min-h-screen bg-warmgray text-textPrimary dark:bg-darkbg dark:text-white">
      <TopNav />
      <main className="mx-auto px-4 pb-16 pt-6">{children}</main>
    </div>
  );
}

export default Layout;
