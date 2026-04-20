import * as React from 'react';

const MOBILE_BREAKPOINT = 768;

export function useIsMobile() {
  const [isMobile, setIsMobile] = React.useState<boolean | undefined>(undefined);

  React.useEffect(() => {
    const mql = window.matchMedia(`(max-width: ${MOBILE_BREAKPOINT - 1}px)`);
    const onChange = (e: MediaQueryListEvent | MediaQueryList) => {
      setIsMobile(e.matches);
    };
    mql.addEventListener('change', onChange as EventListener);
    // Use the media query result directly instead of calling setState synchronously
    onChange(mql);
    return () => mql.removeEventListener('change', onChange as EventListener);
  }, []);

  return !!isMobile;
}
