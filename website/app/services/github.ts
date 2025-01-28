import useSWR from "swr";
import { fetcher } from "./utils";

export function useGithubRelease() {
  return useSWR("https://api.github.com/repos/Caldis/Mos/releases/latest", fetcher, {
    // 30分钟内的重复请求将使用缓存
    dedupingInterval: 1000 * 60 * 30,
    // 禁用焦点重新验证
    revalidateOnFocus: false,
    // 禁用重新连接时重新验证
    revalidateOnReconnect: false,
    // 禁用自动间隔重新验证
    refreshInterval: 0
  });
}