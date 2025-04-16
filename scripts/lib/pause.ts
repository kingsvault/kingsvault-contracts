export const pause = async (ms = 1000): Promise<void> => {
  return new Promise((resolve) => {
    const timeoutId = setTimeout(() => {
      clearTimeout(timeoutId);
      resolve();
    }, ms);
  });
};
