function PageHeader({ title, eyebrow, actions }) {
  return (
    <div className="mb-6 flex flex-col gap-3 border-b border-border pb-4 dark:border-darkborder">
      {eyebrow && <p className="text-xs uppercase tracking-[0.2em] text-textSecondary">{eyebrow}</p>}
      <div className="flex flex-col gap-3 md:flex-row md:items-center md:justify-between">
        <h1 className="font-varsity text-3xl tracking-[0.06em] uppercase">{title}</h1>
        {actions && <div className="flex gap-2">{actions}</div>}
      </div>
    </div>
  );
}

export default PageHeader;
