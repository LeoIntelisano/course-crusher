"""The centered card the sign-in and sign-up forms sit in."""

def:pub AuthCard(title: str, subtitle: str, children: any = None) -> JsxElement {
    <main className="grid min-h-full place-items-center bg-canvas px-4 py-10">
        <section className="w-full max-w-[380px] rounded-lg border border-line-strong bg-surface p-6 shadow-[0_1px_2px_rgba(18,21,26,.05)]" aria-labelledby="auth-title">
            <div className="mb-5 flex items-center gap-[9px]">
                <span className="grid h-[22px] w-[22px] place-items-center rounded-md bg-brand text-[12px] font-bold text-white" aria-hidden="true">C</span>
                <span className="text-[14.5px] font-[650] tracking-[-0.2px]">CourseCrusher</span>
            </div>
            <h1 id="auth-title" className="m-0 text-[20px] font-[650] tracking-[-0.4px]">{title}</h1>
            <p className="mt-1 mb-5 text-[13px] text-muted">{subtitle}</p>
            {children}
        </section>
    </main>
}
