import TopNav from "./TopNav";

function Layout({ children }) {
  return (
    <div className="min-h-screen bg-warmgray text-textPrimary dark:bg-darkbg dark:text-white">
      <TopNav />
      <main className="mx-auto px-4 pb-24 pt-4 md:pb-16">{children}</main>
    </div>
  );
}

export default Layout;
