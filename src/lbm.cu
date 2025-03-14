#include "kernels.cuh"

// ================================================================================================== //

__global__ void phiCalc(
    float * __restrict__ phi,
    const float * __restrict__ g,
    int nx, int ny, int nz
) {
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    int j = blockIdx.y * blockDim.y + threadIdx.y;
    int k = blockIdx.z * blockDim.z + threadIdx.z;

    if (i >= nx || j >= ny || k >= nz || i == 0 || i == nx-1 || j == 0 || j == ny-1 || k == 0 || k == nz-1) return;

    int idx3D = inline3D(i,j,k,nx,ny);

    float sum = 0.0f;       
    for (int l = 0; l < GPOINTS; ++l) {
        int idx4D = inline4D(i,j,k,l,nx,ny,nz);
        sum += g[idx4D];
    }

    phi[idx3D] = sum;
}

// =================================================================================================== //



// =================================================================================================== //

__global__ void gradCalc(
    const float * __restrict__ phi,
    float * __restrict__ normx,
    float * __restrict__ normy,
    float * __restrict__ normz,
    float * __restrict__ indicator,
    int nx, int ny, int nz
) {
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    int j = blockIdx.y * blockDim.y + threadIdx.y;
    int k = blockIdx.z * blockDim.z + threadIdx.z;

    if (i >= nx || j >= ny || k >= nz || i == 0 || i == nx-1 || j == 0 || j == ny-1 || k == 0 || k == nz-1) return;

    int idx3D = inline3D(i,j,k,nx,ny);

    float grad_fix = 0.0f, grad_fiy = 0.0f, grad_fiz = 0.0f;
    for (int l = 0; l < FPOINTS; ++l) {
        int ii = i + CIX[l];
        int jj = j + CIY[l];
        int kk = k + CIZ[l];

        int offset = inline3D(ii,jj,kk,nx,ny);
        float val = phi[offset];
        float coef = 3.0f * W[l];
        grad_fix += coef * CIX[l] * val;
        grad_fiy += coef * CIY[l] * val;
        grad_fiz += coef * CIZ[l] * val;
    }

    float gmag_sq = grad_fix * grad_fix + grad_fiy * grad_fiy + grad_fiz * grad_fiz;
    float factor = rsqrtf(fmaxf(gmag_sq, 1e-9));

    normx[idx3D] = grad_fix * factor;
    normy[idx3D] = grad_fiy * factor;
    normz[idx3D] = grad_fiz * factor;
    indicator[idx3D] = gmag_sq * factor;  
}

// =================================================================================================== //



// =================================================================================================== //

__global__ void curvatureCalc(
    float * __restrict__ curvature,
    const float * __restrict__ indicator,
    const float * __restrict__ normx,
    const float * __restrict__ normy,
    const float * __restrict__ normz,
    float * __restrict__ ffx,
    float * __restrict__ ffy,
    float * __restrict__ ffz,
    int nx, int ny, int nz
) {
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    int j = blockIdx.y * blockDim.y + threadIdx.y;
    int k = blockIdx.z * blockDim.z + threadIdx.z;

    if (i >= nx || j >= ny || k >= nz || i == 0 || i == nx-1 || j == 0 || j == ny-1 || k == 0 || k == nz-1) return;

    int idx3D = inline3D(i,j,k,nx,ny);

    float normx_ = normx[idx3D];
    float normy_ = normy[idx3D];
    float normz_ = normz[idx3D];
    float ind_ = indicator[idx3D];
    float curv = 0.0f;

    for (int l = 0; l < FPOINTS; ++l) {
        int ii = i + CIX[l];
        int jj = j + CIY[l];
        int kk = k + CIZ[l];

        int offset = inline3D(ii,jj,kk,nx,ny);
        float normxN = normx[offset];
        float normyN = normy[offset];
        float normzN = normz[offset];
        float coef = 3.0f * W[l];
        curv -= coef * (CIX[l] * normxN + CIY[l] * normyN + CIZ[l] * normzN);
    }

    float mult = SIGMA * curv;

    curvature[idx3D] = curv;
    ffx[idx3D] = mult * normx_ * ind_;
    ffy[idx3D] = mult * normy_ * ind_;
    ffz[idx3D] = mult * normz_ * ind_;
}

// =================================================================================================== //



// =================================================================================================== //

__global__ void momentiCalc(
    float * __restrict__ ux,
    float * __restrict__ uy,
    float * __restrict__ uz,
    float * __restrict__ rho,
    float * __restrict__ ffx,
    float * __restrict__ ffy,
    float * __restrict__ ffz,
    const float * __restrict__ f,
    float * __restrict__ pxx,
    float * __restrict__ pyy,
    float * __restrict__ pzz,
    float * __restrict__ pxy,
    float * __restrict__ pxz,
    float * __restrict__ pyz,
    int nx, int ny, int nz
) {
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    int j = blockIdx.y * blockDim.y + threadIdx.y;
    int k = blockIdx.z * blockDim.z + threadIdx.z;
    
    if (i >= nx || j >= ny || k >= nz || i == 0 || i == nx-1 || j == 0 || j == ny-1 || k == 0 || k == nz-1) return;

    int idx3D = inline3D(i,j,k,nx,ny);
    
    float fneq[FPOINTS];
    float fVal[FPOINTS];

    for (int l = 0; l < FPOINTS; ++l) {
        int idx4D = inline4D(i,j,k,l,nx,ny,nz);
        fVal[l] = f[idx4D];
    }

    float rhoVal = 0.0f;
    float rhoShift = 0.0f;
    for (int l = 0; l < FPOINTS; ++l)
        rhoShift += fVal[l];
    rhoVal = rhoShift + 1.0f;

    float invRho = 1.0f / rhoVal;

    float sumUx = invRho * (fVal[1] - fVal[2] + fVal[7] - fVal[8] + fVal[9] - fVal[10] + fVal[13] - fVal[14] + fVal[15] - fVal[16]);
    float sumUy = invRho * (fVal[3] - fVal[4] + fVal[7] - fVal[8] + fVal[11] - fVal[12] + fVal[14] - fVal[13] + fVal[17] - fVal[18]);
    float sumUz = invRho * (fVal[5] - fVal[6] + fVal[9] - fVal[10] + fVal[11] - fVal[12] + fVal[16] - fVal[15] + fVal[18] - fVal[17]);

    float ffx_val = ffx[idx3D];
    float ffy_val = ffy[idx3D];
    float ffz_val = ffz[idx3D];

    float halfFx = ffx_val * 0.5f * invRho;
    float halfFy = ffy_val * 0.5f * invRho;
    float halfFz = ffz_val * 0.5f * invRho;

    float uxVal = sumUx + halfFx;
    float uyVal = sumUy + halfFy;
    float uzVal = sumUz + halfFz;

    float invCssq = 1.0f / CSSQ;
    float uu = 0.5f * (uxVal * uxVal + uyVal * uyVal + uzVal * uzVal) * invCssq;
    float invRhoCssq = 1.0f / (rhoVal * CSSQ);

    float sumXX = 0.0f, sumYY = 0.0f, sumZZ = 0.0f;
    float sumXY = 0.0f, sumXZ = 0.0f, sumYZ = 0.0f;

    for (int l = 0; l < FPOINTS; ++l) {
        float udotc = (uxVal * CIX[l] + uyVal * CIY[l] + uzVal * CIZ[l]) * invCssq;
        float eqBase = rhoVal * (udotc + 0.5f * udotc*udotc - uu);
        float common = W[l] * (rhoVal + eqBase);
        float HeF = common * ((CIX[l] - uxVal) * ffx_val +
                              (CIY[l] - uyVal) * ffy_val +
                              (CIZ[l] - uzVal) * ffz_val) * invRhoCssq;
        float feq = common - 0.5f * HeF; 
        float feq_shifted = feq - W[l];
        fneq[l] = fVal[l] - feq_shifted;
    }

    sumXX = fneq[1] + fneq[2] + fneq[7] + fneq[8] + fneq[9] + fneq[10] + fneq[13] + fneq[14] + fneq[15] + fneq[16];
    sumYY = fneq[3] + fneq[4] + fneq[7] + fneq[8] + fneq[11] + fneq[12] + fneq[13] + fneq[14] + fneq[17] + fneq[18];
    sumZZ = fneq[5] + fneq[6] + fneq[9] + fneq[10] + fneq[11] + fneq[12] + fneq[15] + fneq[16] + fneq[17] + fneq[18];
    sumXY = fneq[7] - fneq[13] + fneq[8] - fneq[14];
    sumXZ = fneq[9] - fneq[15] + fneq[10] - fneq[16];
    sumYZ = fneq[11] - fneq[17] + fneq[12] - fneq[18];

    pxx[idx3D] = sumXX; pyy[idx3D] = sumYY; pzz[idx3D] = sumZZ;
    pxy[idx3D] = sumXY; pxz[idx3D] = sumXZ; pyz[idx3D] = sumYZ;

    ux[idx3D] = uxVal; uy[idx3D] = uyVal; uz[idx3D] = uzVal;
    rho[idx3D] = rhoVal;
}

// =================================================================================================== //



// =================================================================================================== //

__global__ void collisionFluid(
    float * __restrict__ f,
    const float * __restrict__ ux,
    const float * __restrict__ uy,
    const float * __restrict__ uz,
    const float * __restrict__ ffx,
    const float * __restrict__ ffy,
    const float * __restrict__ ffz,
    const float * __restrict__ rho,
    const float * __restrict__ pxx,
    const float * __restrict__ pyy,
    const float * __restrict__ pzz,
    const float * __restrict__ pxy,
    const float * __restrict__ pxz,
    const float * __restrict__ pyz,
    int nx, int ny, int nz
) {
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    int j = blockIdx.y * blockDim.y + threadIdx.y;
    int k = blockIdx.z * blockDim.z + threadIdx.z;

    if (i >= nx || j >= ny || k >= nz || i == 0 || i == nx-1 || j == 0 || j == ny-1 || k == 0 || k == nz-1) return;

    int idx3D = inline3D(i,j,k,nx,ny);

    float ux_val = ux[idx3D], uy_val = uy[idx3D], uz_val = uz[idx3D], rho_val = rho[idx3D];
    float ffx_val = ffx[idx3D], ffy_val = ffy[idx3D], ffz_val = ffz[idx3D];
    float pxx_val = pxx[idx3D], pyy_val = pyy[idx3D], pzz_val = pzz[idx3D];
    float pxy_val = pxy[idx3D], pxz_val = pxz[idx3D], pyz_val = pyz[idx3D];

    float uu = 0.5f * (ux_val*ux_val + uy_val*uy_val + uz_val*uz_val) / CSSQ;
    float invRhoCssq = 1.0f / (rho_val * CSSQ);
    float invCssq = 1.0f / CSSQ;

    for (int l = 0; l < FPOINTS; ++l) {
        int ii = i + CIX[l]; 
        int jj = j + CIY[l]; 
        int kk = k + CIZ[l];
        
        float udotc = (ux_val * CIX[l] + uy_val * CIY[l] + uz_val * CIZ[l]) * invCssq;
        float feq = (W[l] * (rho_val + rho_val * (udotc + 0.5f * udotc*udotc - uu))) - W[l];
        float HeF = feq * ( (CIX[l] - ux_val) * ffx_val +
                            (CIY[l] - uy_val) * ffy_val +
                            (CIZ[l] - uz_val) * ffz_val ) * invRhoCssq;
        float fneq = (W[l] / (2.0f * CSSQ * CSSQ)) * ((CIX[l]*CIX[l] - CSSQ) * pxx_val +
                                                      (CIY[l]*CIY[l] - CSSQ) * pyy_val +
                                                      (CIZ[l]*CIZ[l] - CSSQ) * pzz_val +
                                                       2.0f * CIX[l] * CIY[l] * pxy_val +
                                                       2.0f * CIX[l] * CIZ[l] * pxz_val +
                                                       2.0f * CIY[l] * CIZ[l] * pyz_val
                                                    );
        int offset = inline4D(ii,jj,kk,l,nx,ny,nz);
        f[offset] = feq + (1.0f - OMEGA) * fneq + 0.5f * HeF; 
    }
}

__global__ void collisionPhase(
    float * __restrict__ g,
    const float * __restrict__ ux,
    const float * __restrict__ uy,
    const float * __restrict__ uz,
    const float * __restrict__ phi,
    const float * __restrict__ normx,
    const float * __restrict__ normy,
    const float * __restrict__ normz,
    int nx, int ny, int nz
) {
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    int j = blockIdx.y * blockDim.y + threadIdx.y;
    int k = blockIdx.z * blockDim.z + threadIdx.z;

    if (i >= nx || j >= ny || k >= nz || i == 0 || i == nx-1 || j == 0 || j == ny-1 || k == 0 || k == nz-1) return;

    int idx3D = inline3D(i,j,k,nx,ny);

    float ux_val = ux[idx3D];
    float uy_val = uy[idx3D];
    float uz_val = uz[idx3D];
    float phi_val = phi[idx3D];
    float normx_val = normx[idx3D]; 
    float normy_val = normy[idx3D];
    float normz_val = normz[idx3D];

    float invCSSQ = 1.0f / CSSQ;

    float phi_norm = SHARP_C * phi_val * (1.0f - phi_val);
    for (int l = 0; l < GPOINTS; ++l) {
        int idx4D = inline4D(i,j,k,l,nx,ny,nz);
        float udotc = (ux_val * CIX[l] + uy_val * CIY[l] + uz_val * CIZ[l]) * invCSSQ;
        float geq = W_G[l] * phi_val * (1.0f + udotc);
        float Hi = phi_norm * (CIX[l] * normx_val + CIY[l] * normy_val + CIZ[l] * normz_val);
        g[idx4D] = geq + W_G[l] * Hi; // + (1 - omega) * gneq;
        // there is an option to stream g in collision as f is being done
    }
}

// =================================================================================================== //



// =================================================================================================== //

__global__ void streamingCalc(
    const float * __restrict__ g,
    float * __restrict__ g_out,
    int nx, int ny, int nz
) {
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    int j = blockIdx.y * blockDim.y + threadIdx.y;
    int k = blockIdx.z * blockDim.z + threadIdx.z;

    if (i >= nx || j >= ny || k >= nz) return;

    for (int l = 0; l < GPOINTS; ++l) {
        int src_i = (i - CIX[l] + nx) & (nx-1);
        int src_j = (j - CIY[l] + ny) & (ny-1);
        int src_k = (k - CIZ[l] + nz) & (nz-1);
        int dstIdx = inline4D(i,j,k,l,nx,ny,nz);
        int srcIdx = inline4D(src_i,src_j,src_k,l,nx,ny,nz);
        g_out[dstIdx] = g[srcIdx];
    }
}

// =================================================================================================== //



// =================================================================================================== //

__global__ void fgBoundary(
    float * __restrict__ f,
    const float * __restrict__ rho,
    float * __restrict__ g,
    const float * __restrict__ phi,
    int nx, int ny, int nz
) {
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    int j = blockIdx.y * blockDim.y + threadIdx.y;
    int k = blockIdx.z * blockDim.z + threadIdx.z;

    bool isValidEdge = (i < nx && j < ny && k < nz) && (i == 0 || i == nx-1 || j == 0 || j == ny-1 || k == 0 || k == nz-1);
    if (!isValidEdge) return;

    int idx3D = inline3D(i,j,k,nx,ny);

    for (int l = 0; l < FPOINTS; ++l) {
        int ni = i + CIX[l];
        int nj = j + CIY[l];
        int nk = k + CIZ[l];
        if (ni >= 0 && ni < nx && nj >= 0 && nj < ny && nk >= 0 && nk < nz) {
            int idx4D = inline4D(ni,nj,nk,l,nx,ny,nz);
            f[idx4D] = (rho[idx3D] - 1.0f) * W[l];
        }
    }
    for (int l = 0; l < GPOINTS; ++l) {
        int ni = i + CIX[l];
        int nj = j + CIY[l];
        int nk = k + CIZ[l];
        if (ni >= 0 && ni < nx && nj >= 0 && nj < ny && nk >= 0 && nk < nz) {
            int idx4D = inline4D(ni,nj,nk,l,nx,ny,nz);
            g[idx4D] = phi[idx3D] * W_G[l];
        }
    }
}

__global__ void boundaryConditions(
    float * __restrict__ phi,
    int nx, int ny, int nz
) {
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    int j = blockIdx.y * blockDim.y + threadIdx.y;
    int k = blockIdx.z * blockDim.z + threadIdx.z;

    if (i < nx && j < ny) {
        phi[IDX3D(i,j,0)] = phi[IDX3D(i,j,1)];
        phi[IDX3D(i,j,nz-1)] = phi[IDX3D(i,j,nz-2)];
    }

    if (i < nx && k < nz) {
        phi[IDX3D(i,0,k)] = phi[IDX3D(i,1,k)];
        phi[IDX3D(i,ny-1,k)] = phi[IDX3D(i,ny-2,k)];
    }

    if (j < ny && k < nz) {
        phi[IDX3D(0,j,k)] = phi[IDX3D(1,j,k)];
        phi[IDX3D(nx-1,j,k)] = phi[IDX3D(nx-2,j,k)];
    }
}


// =================================================================================================== //

