<apply template="base">
  <bind tag="body-main">
    <div class="container mx-auto">

      <apply template="components/breadcrumbs" />

      <div class="flex bg-gray-50 md:mt-8 md:shadow-2xl md:mb-8">
        <!-- Sidebar column -->
        <nav id="sidebar"
          class="hidden leading-relaxed md:block md:sticky md:top-0 md:h-full md:max-w-xs">
          <div class="px-2 py-2 text-gray-800">

            <div id="indexing-links" class="flex flex-row float-right p-2 space-x-2 text-gray-500">
              <a href="-/tags" title="View tags">
                <svg class="w-5 h-5 hover:text-${theme}-700" fill="none" stroke="currentColor"
                  viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2"
                    d="M7 7h.01M7 3h5c.512 0 1.024.195 1.414.586l7 7a2 2 0 010 2.828l-7 7a2 2 0 01-2.828 0l-7-7A1.994 1.994 0 013 12V7a4 4 0 014-4z">
                  </path>
                </svg>
              </a>
              <a href="-/index" title="Expand full tree">
                <svg class="w-5 h-5 hover:text-${theme}-700" fill="none" stroke="currentColor"
                  viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2"
                    d="M4 8V4m0 0h4M4 4l5 5m11-1V4m0 0h-4m4 0l-5 5M4 16v4m0 0h4m-4 0l5-5m11 5l-5-5m5 5v-4m0 4h-4">
                  </path>
                </svg>
              </a>
            </div>

            <div id="site-logo" class="pl-2">
              <div class="flex items-center my-2 space-x-2 justify-left">
                <a href="" title="Go to Home">
                  <ema:metadata>
                    <with var="template">
                      <!-- The style width attribute here is to prevent huge
                      icon from displaying at those rare occasions when Tailwind
                      hasn't kicked in immediately on page load 
                      -->
                   <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg">
		   <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M3 12l2-2m0 0l7-7 7 7M5 10v10a1 1 0 001 1h3m10-11l2 2m-2-2v10a1 1 0 01-1 1h-3m-6 0a1 1 0 001-1v-4a1 1 0 011-1h2a1 1 0 011 1v4a1 1 0 001 1m-6 0h6">
			</path>
		      </svg> 
		   </with>
                  </ema:metadata>
                </a>
                <a class="font-bold truncate" title="Go to Home" href="">
                  Home
                </a>
              </div>
            </div>

            <ema:route-tree>
              <apply template="components/sidebar-tree" />
            </ema:route-tree>

          </div>
        </nav>

        <!-- Main body column -->
        <div class="w-full bg-white">
          <main class="px-4 py-4">
            <apply template="components/note-title" />
            <apply template="components/note-body" />
            <apply template="components/backlinks" />
            <apply template="components/metadata" />
          </main>
        </div>
      </div>
      <apply template="components/footer" />
    </div>
  </bind>
</apply>
